#include "audio_meter_plugin.h"

#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <audioclient.h>
#include <ksmedia.h>
#include <wincrypt.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstring>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()),
                                         nullptr, 0);
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), length);
  return result;
}

float GetOutputPeak(const std::string& requested_device) {
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioMeterInformation* meter = nullptr;
  float peak = 0.0f;

  HRESULT hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                reinterpret_cast<void**>(&enumerator));
  if (FAILED(hr)) return peak;

  std::wstring device_id = Utf8ToWide(requested_device);
  const std::wstring wasapi_prefix = L"wasapi/";
  if (device_id.rfind(wasapi_prefix, 0) == 0) {
    device_id = device_id.substr(wasapi_prefix.size());
  }

  if (!device_id.empty() && device_id != L"auto") {
    enumerator->GetDevice(device_id.c_str(), &device);
  }
  if (!device) {
    enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
  }
  if (device &&
      SUCCEEDED(device->Activate(__uuidof(IAudioMeterInformation), CLSCTX_ALL,
                                 nullptr, reinterpret_cast<void**>(&meter)))) {
    meter->GetPeakValue(&peak);
  }

  if (meter) meter->Release();
  if (device) device->Release();
  enumerator->Release();
  return peak;
}

constexpr size_t kSpectrumBandCount = 64;
constexpr size_t kFftSize = 1024;

std::vector<double> EmptySpectrum() {
  return std::vector<double>(kSpectrumBandCount, 0.0);
}

float DecodeAudioSample(const BYTE* input, const WAVEFORMATEX* format,
                        bool is_float) {
  if (is_float && format->wBitsPerSample == 32) {
    float value = 0.0f;
    std::memcpy(&value, input, sizeof(value));
    return value;
  }
  if (is_float && format->wBitsPerSample == 64) {
    double value = 0.0;
    std::memcpy(&value, input, sizeof(value));
    return static_cast<float>(value);
  }
  switch (format->wBitsPerSample) {
    case 8:
      return (static_cast<int>(*input) - 128) / 128.0f;
    case 16: {
      int16_t value = 0;
      std::memcpy(&value, input, sizeof(value));
      return value / 32768.0f;
    }
    case 24: {
      int32_t value = static_cast<int32_t>(input[0]) |
                      (static_cast<int32_t>(input[1]) << 8) |
                      (static_cast<int32_t>(input[2]) << 16);
      if ((value & 0x00800000) != 0) value |= 0xff000000;
      return value / 8388608.0f;
    }
    case 32: {
      int32_t value = 0;
      std::memcpy(&value, input, sizeof(value));
      return value / 2147483648.0f;
    }
    default:
      return 0.0f;
  }
}

std::vector<double> CalculateSpectrum(const std::vector<float>& samples) {
  if (samples.size() < kFftSize) return EmptySpectrum();

  std::array<std::complex<double>, kFftSize> values{};
  const size_t offset = samples.size() - kFftSize;
  for (size_t i = 0; i < kFftSize; ++i) {
    // Hann window reduces the visual leakage between adjacent FFT bands.
    const double window = 0.5 - 0.5 * std::cos(2.0 * std::acos(-1.0) * i /
                                                (kFftSize - 1));
    values[i] = static_cast<double>(samples[offset + i]) * window;
  }

  for (size_t i = 1, bit = 0; i < kFftSize; ++i) {
    size_t mask = kFftSize >> 1;
    for (; bit & mask; mask >>= 1) bit ^= mask;
    bit ^= mask;
    if (i < bit) std::swap(values[i], values[bit]);
  }
  for (size_t length = 2; length <= kFftSize; length <<= 1) {
    const std::complex<double> step = std::polar(
        1.0, -2.0 * std::acos(-1.0) / static_cast<double>(length));
    for (size_t start = 0; start < kFftSize; start += length) {
      std::complex<double> rotation = 1.0;
      for (size_t index = 0; index < length / 2; ++index) {
        const auto even = values[start + index];
        const auto odd = values[start + index + length / 2] * rotation;
        values[start + index] = even + odd;
        values[start + index + length / 2] = even - odd;
        rotation *= step;
      }
    }
  }

  std::vector<double> spectrum;
  spectrum.reserve(kSpectrumBandCount);
  constexpr size_t max_bin = kFftSize / 2 - 1;
  for (size_t band = 0; band < kSpectrumBandCount; ++band) {
    const auto band_edge = [&](size_t index) {
      return static_cast<size_t>(std::pow(
          static_cast<double>(max_bin),
          static_cast<double>(index) / static_cast<double>(kSpectrumBandCount)));
    };
    const size_t begin = std::max<size_t>(1, band_edge(band));
    const size_t end = std::min<size_t>(
        max_bin, std::max(begin, band_edge(band + 1)));
    double strongest = 0.0;
    for (size_t bin = begin; bin <= end; ++bin) {
      strongest = std::max(strongest, std::abs(values[bin]) / kFftSize);
    }
    const double decibels = 20.0 * std::log10(strongest + 0.000001);
    spectrum.push_back(std::clamp((decibels + 70.0) / 62.0, 0.0, 1.0));
  }
  return spectrum;
}

std::vector<double> GetOutputSpectrum(const std::string& requested_device) {
  const HRESULT com_status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool should_uninitialize = SUCCEEDED(com_status);
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioClient* client = nullptr;
  IAudioCaptureClient* capture = nullptr;
  WAVEFORMATEX* format = nullptr;
  std::vector<float> samples;
  samples.reserve(kFftSize * 2);

  auto cleanup = [&]() {
    if (client) client->Stop();
    if (capture) capture->Release();
    if (format) CoTaskMemFree(format);
    if (client) client->Release();
    if (device) device->Release();
    if (enumerator) enumerator->Release();
    if (should_uninitialize) CoUninitialize();
  };

  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                              reinterpret_cast<void**>(&enumerator)))) {
    cleanup();
    return EmptySpectrum();
  }
  std::wstring device_id = Utf8ToWide(requested_device);
  const std::wstring wasapi_prefix = L"wasapi/";
  if (device_id.rfind(wasapi_prefix, 0) == 0) {
    device_id = device_id.substr(wasapi_prefix.size());
  }
  if (!device_id.empty() && device_id != L"auto") {
    enumerator->GetDevice(device_id.c_str(), &device);
  }
  if (!device) enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
  if (!device || FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL,
                                          nullptr,
                                          reinterpret_cast<void**>(&client))) ||
      FAILED(client->GetMixFormat(&format))) {
    cleanup();
    return EmptySpectrum();
  }
  if (FAILED(client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                AUDCLNT_STREAMFLAGS_LOOPBACK, 0, 0, format,
                                nullptr)) ||
      FAILED(client->GetService(__uuidof(IAudioCaptureClient),
                                reinterpret_cast<void**>(&capture))) ||
      FAILED(client->Start())) {
    cleanup();
    return EmptySpectrum();
  }

  const bool is_float = format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT ||
      (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
       reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format)->SubFormat ==
           KSDATAFORMAT_SUBTYPE_IEEE_FLOAT);
  const size_t bytes_per_sample = format->wBitsPerSample / 8;
  const auto deadline = std::chrono::steady_clock::now() +
      // 1024 frames need about 23 ms at 44.1 kHz. Keep the synchronous method
      // call well below the 70 ms UI sampling interval even on slower devices.
      std::chrono::milliseconds(60);
  while (samples.size() < kFftSize && std::chrono::steady_clock::now() < deadline) {
    UINT32 packet_frames = 0;
    if (FAILED(capture->GetNextPacketSize(&packet_frames))) break;
    if (packet_frames == 0) {
      Sleep(3);
      continue;
    }
    BYTE* data = nullptr;
    UINT32 frames = 0;
    DWORD flags = 0;
    if (FAILED(capture->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) break;
    for (UINT32 frame = 0; frame < frames; ++frame) {
      float mixed = 0.0f;
      if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0) {
        for (WORD channel = 0; channel < format->nChannels; ++channel) {
          const BYTE* sample = data + frame * format->nBlockAlign +
              channel * bytes_per_sample;
          mixed += DecodeAudioSample(sample, format, is_float);
        }
        mixed /= std::max<WORD>(1, format->nChannels);
      }
      samples.push_back(mixed);
    }
    capture->ReleaseBuffer(frames);
  }
  cleanup();
  return CalculateSpectrum(samples);
}

std::string ReadDeviceId(const flutter::EncodableValue* arguments) {
  if (!arguments) return {};
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (!map) return {};
  const auto it = map->find(flutter::EncodableValue("deviceId"));
  if (it == map->end()) return {};
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string{};
}

// Keep the authentication session in a fixed per-user location instead of the
// application bundle. DPAPI binds the encrypted contents to the signed-in
// Windows user, so copying a build to another folder (or replacing it during
// an upgrade) neither exposes nor loses the session.
std::wstring SessionFilePath() {
  wchar_t local_app_data[MAX_PATH]{};
  const DWORD length = GetEnvironmentVariableW(
      L"LOCALAPPDATA", local_app_data, static_cast<DWORD>(std::size(local_app_data)));
  if (length == 0 || length >= std::size(local_app_data)) return {};

  const std::wstring directory = std::wstring(local_app_data, length) + L"\\FnMusic";
  if (!CreateDirectoryW(directory.c_str(), nullptr) &&
      GetLastError() != ERROR_ALREADY_EXISTS) {
    return {};
  }
  return directory + L"\\auth-session.v1";
}

bool WriteProtectedSession(const std::string& session) {
  const std::wstring path = SessionFilePath();
  if (path.empty()) return false;

  DATA_BLOB input{};
  input.cbData = static_cast<DWORD>(session.size());
  input.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(session.data()));
  DATA_BLOB encrypted{};
  if (!CryptProtectData(&input, L"FnMusic authentication session", nullptr,
                        nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN,
                        &encrypted)) {
    return false;
  }

  const std::wstring temporary_path = path + L".tmp";
  std::ofstream file(temporary_path, std::ios::binary | std::ios::trunc);
  if (!file) {
    LocalFree(encrypted.pbData);
    return false;
  }
  file.write(reinterpret_cast<const char*>(encrypted.pbData), encrypted.cbData);
  file.close();
  LocalFree(encrypted.pbData);
  if (!file) {
    DeleteFileW(temporary_path.c_str());
    return false;
  }
  if (!MoveFileExW(temporary_path.c_str(), path.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temporary_path.c_str());
    return false;
  }
  return true;
}

std::string ReadProtectedSession() {
  const std::wstring path = SessionFilePath();
  if (path.empty()) return {};

  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (!file) return {};
  const std::streamsize size = file.tellg();
  // An authentication session is tiny; reject corrupted or unexpected data.
  if (size <= 0 || size > 1024 * 1024) return {};
  file.seekg(0, std::ios::beg);
  std::vector<BYTE> encrypted(static_cast<size_t>(size));
  if (!file.read(reinterpret_cast<char*>(encrypted.data()), size)) return {};

  DATA_BLOB input{};
  input.cbData = static_cast<DWORD>(encrypted.size());
  input.pbData = encrypted.data();
  DATA_BLOB decrypted{};
  if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &decrypted)) {
    return {};
  }
  std::string session(reinterpret_cast<const char*>(decrypted.pbData),
                      decrypted.cbData);
  LocalFree(decrypted.pbData);
  return session;
}

bool ClearProtectedSession() {
  const std::wstring path = SessionFilePath();
  return path.empty() || DeleteFileW(path.c_str()) ||
         GetLastError() == ERROR_FILE_NOT_FOUND;
}

}  // namespace

void AudioMeterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "fnmusic/audio_meter",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() == "getOutputPeak") {
          result->Success(flutter::EncodableValue(
              static_cast<double>(GetOutputPeak(ReadDeviceId(call.arguments())))));
          return;
        }
        if (call.method_name() == "getOutputSpectrum") {
          const auto values = GetOutputSpectrum(ReadDeviceId(call.arguments()));
          flutter::EncodableList spectrum;
          spectrum.reserve(values.size());
          for (const double value : values) {
            spectrum.emplace_back(value);
          }
          result->Success(flutter::EncodableValue(spectrum));
          return;
        }
        result->NotImplemented();
      });

  auto session_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "fnmusic/session_store",
          &flutter::StandardMethodCodec::GetInstance());
  session_channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() == "read") {
          const std::string session = ReadProtectedSession();
          if (session.empty()) {
            result->Success();
          } else {
            result->Success(flutter::EncodableValue(session));
          }
          return;
        }
        if (call.method_name() == "write") {
          const auto* session = std::get_if<std::string>(call.arguments());
          if (!session || !WriteProtectedSession(*session)) {
            result->Error("session_write_failed",
                          "Could not securely save the login session.");
          } else {
            result->Success();
          }
          return;
        }
        if (call.method_name() == "clear") {
          if (!ClearProtectedSession()) {
            result->Error("session_clear_failed",
                          "Could not remove the login session.");
          } else {
            result->Success();
          }
          return;
        }
        result->NotImplemented();
      });

  // The registrar takes ownership of the handler; the channel only needs to
  // live for registration, as Flutter keeps the messenger callback alive.
}
