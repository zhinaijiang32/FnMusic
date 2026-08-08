#ifndef RUNNER_AUDIO_METER_PLUGIN_H_
#define RUNNER_AUDIO_METER_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

class AudioMeterPlugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);
};

#endif  // RUNNER_AUDIO_METER_PLUGIN_H_
