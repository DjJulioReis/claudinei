#ifndef PREFERENCES_MANAGER_H
#define PREFERENCES_MANAGER_H

#include <Preferences.h>
#include "WinchConfig.h"

class PreferencesManager {
private:
  Preferences preferences;

public:
  int dmxAddress = 1;
  double maxSpeedMM = 150.0;    // mm/s
  double accelerationMM = 100.0; // mm/s^2
  double decelerationMM = 100.0; // mm/s^2

  void begin() {
    preferences.begin("mileto_cfg", false);
    dmxAddress = preferences.getInt("dmx", 1);
    maxSpeedMM = preferences.getDouble("max_speed", 150.0);
    accelerationMM = preferences.getDouble("acceleration", 100.0);
    decelerationMM = preferences.getDouble("deceleration", 100.0);
    preferences.end();
  }

  void saveDMX(int dmx) {
    dmxAddress = dmx;
    preferences.begin("mileto_cfg", false);
    preferences.putInt("dmx", dmxAddress);
    preferences.end();
  }

  void saveTrapezoidalParams(double speed, double accel, double decel) {
    maxSpeedMM = speed;
    accelerationMM = accel;
    decelerationMM = decel;
    preferences.begin("mileto_cfg", false);
    preferences.putDouble("max_speed", maxSpeedMM);
    preferences.putDouble("acceleration", accelerationMM);
    preferences.putDouble("deceleration", decelerationMM);
    preferences.end();
  }
};

extern PreferencesManager prefManager;

#endif // PREFERENCES_MANAGER_H