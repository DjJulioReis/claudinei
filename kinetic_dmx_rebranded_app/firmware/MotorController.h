#ifndef MOTOR_CONTROLLER_H
#define MOTOR_CONTROLLER_H

#include <Arduino.h>
#include "WinchConfig.h"
#include "EncoderManager.h"
#include "PreferencesManager.h"

class MotorController {
private:
  unsigned long lastStepTime = 0;
  unsigned long lastUpdateTime = 0;
  double currentSpeed = 0.0; // mm/s

public:
  int currentPosition = 0;   // Passos estimados
  double targetPosMM = 0.0;  // Alvo em milímetros
  bool isCalibrated = false;
  bool isHoming = false;

  void begin() {
    pinMode(STEP_PIN, OUTPUT);
    pinMode(DIR_PIN, OUTPUT);
    pinMode(SENSOR_HOME, INPUT_PULLUP);

    digitalWrite(STEP_PIN, LOW);
    digitalWrite(DIR_PIN, LOW);

    lastUpdateTime = micros();
  }

  void stop() {
    if (isHoming) {
      isHoming = false;
      isCalibrated = true;
      noInterrupts();
      encoder.encoderCount = 0;
      interrupts();
      currentPosition = 0;
      Serial.println("ℹ️ HOMING ABORTADO pelo usuário. Calibração na posição atual.");
    }
    targetPosMM = USAR_ENCODER ? encoder.getPositionMM() : ((double)currentPosition / STEPS_PER_MM);
    currentSpeed = 0.0;
  }

  void runClosedLoop() {
    if (encoder.encoderError) {
      currentSpeed = 0.0;
      return;
    }

    unsigned long now = micros();
    double dt = (double)(now - lastUpdateTime) / 1000000.0;
    if (dt <= 0.0) dt = 0.0001;
    lastUpdateTime = now;

    if (isHoming) {
      runHomingRoutine();
      return;
    }

    if (!isCalibrated) {
      currentSpeed = 0.0;
      return;
    }

    double realPosMM = USAR_ENCODER ? encoder.getPositionMM() : ((double)currentPosition / STEPS_PER_MM);
    double errorMM = targetPosMM - realPosMM;
    double errorAbs = abs(errorMM);

    if (errorAbs <= POSITION_TOLERANCE_MM) {
      currentSpeed = 0.0;
      return;
    }

    bool subindo = errorMM > 0;
    digitalWrite(DIR_PIN, subindo ? HIGH : LOW);

    double brakingDistance = (currentSpeed * currentSpeed) / (2.0 * prefManager.decelerationMM);

    if (errorAbs <= brakingDistance) {
      currentSpeed = max(10.0, currentSpeed - (prefManager.decelerationMM * dt));
    } else {
      currentSpeed = min(prefManager.maxSpeedMM, currentSpeed + (prefManager.accelerationMM * dt));
    }

    double stepsPerSecond = currentSpeed * STEPS_PER_MM;
    if (stepsPerSecond <= 0.0) return;

    unsigned long stepIntervalMicros = (unsigned long)(1000000.0 / stepsPerSecond);

    if (now - lastStepTime >= stepIntervalMicros) {
      lastStepTime = now;

      digitalWrite(STEP_PIN, HIGH);
      delayMicroseconds(2);
      digitalWrite(STEP_PIN, LOW);

      if (subindo) {
        currentPosition++;
      } else {
        currentPosition--;
      }
    }
  }

  void runHomingRoutine() {
    unsigned long now = micros();
    double homingSpeed = 15.0;
    double stepsPerSecond = homingSpeed * STEPS_PER_MM;
    unsigned long stepIntervalMicros = (unsigned long)(1000000.0 / stepsPerSecond);

    if (digitalRead(SENSOR_HOME) == HIGH) {
      if (now - lastStepTime >= stepIntervalMicros) {
        lastStepTime = now;
        digitalWrite(DIR_PIN, LOW);
        digitalWrite(STEP_PIN, HIGH);
        delayMicroseconds(2);
        digitalWrite(STEP_PIN, LOW);
        currentPosition--;
      }
    } else {
      noInterrupts();
      encoder.encoderCount = 0;
      interrupts();

      currentPosition = 0;
      targetPosMM = 0.0;
      isHoming = false;
      isCalibrated = true;
      currentSpeed = 0.0;

      Serial.println("🏆 HOMING REALIZADO! Origem estabelecida.");
    }
  }

  void monitorSafety() {
    if (!USAR_ENCODER) return;
    if (!isCalibrated || isHoming || encoder.encoderError) return;

    double encoderPosMM = encoder.getPositionMM();
    double currentPosMM = (double)currentPosition / STEPS_PER_MM;

    double error = abs(currentPosMM - encoderPosMM);
    if (error > MAX_ENCODER_ERROR_MM) {
      encoder.encoderError = true;
      stop();
      Serial.print("🚨 DESENCONTRO DETECTADO! Erro de ");
      Serial.print(error);
      Serial.println(" mm. Motor mantido travado sob retenção.");
    }
  }
};

extern MotorController motorController;

#endif // MOTOR_CONTROLLER_H