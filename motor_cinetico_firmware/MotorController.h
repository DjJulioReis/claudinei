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
  int currentPosition = 0;   // Passos estimados (posição teórica)
  double targetPosMM = 0.0;  // Alvo absoluto em milímetros
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
      Serial.println("ℹ️ HOMING ABORTADO pelo usuário. Calibração forçada na posição atual.");
    }
    targetPosMM = USAR_ENCODER ? encoder.getPositionMM() : ((double)currentPosition / STEPS_PER_MM);
    currentSpeed = 0.0;
  }

  void runClosedLoop() {
    // Mesmo com erro de encoder, os passos apenas param, mas a energia do motor continua ativa para segurar a carga no ar!
    if (encoder.encoderError) {
      currentSpeed = 0.0;
      return;
    }

    unsigned long now = micros();
    double dt = (double)(now - lastUpdateTime) / 1000000.0;
    if (dt <= 0.0) dt = 0.0001; // Proteção contra divisão por zero
    lastUpdateTime = now;

    // Se estiver fazendo homing, ignora a malha fechada temporariamente
    if (isHoming) {
      runHomingRoutine();
      return;
    }

    // Se não estiver calibrado, não permite movimentação em malha fechada
    if (!isCalibrated) {
      currentSpeed = 0.0;
      return;
    }

    // Calcula a posição real (seja pelo encoder físico ou pela posição teórica estimada por passos)
    double realPosMM = USAR_ENCODER ? encoder.getPositionMM() : ((double)currentPosition / STEPS_PER_MM);

    // Calcula o erro em milímetros (Alvo - Real)
    double errorMM = targetPosMM - realPosMM;
    double errorAbs = abs(errorMM);

    // Se estiver dentro da tolerância de posicionamento industrial, para o motor
    if (errorAbs <= POSITION_TOLERANCE_MM) {
      currentSpeed = 0.0;
      return;
    }

    // Determina a direção física
    bool subindo = errorMM > 0;
    digitalWrite(DIR_PIN, subindo ? HIGH : LOW);

    // --- PERFIL DE VELOCIDADE TRAPEZOIDAL ---
    // Distância necessária para desacelerar até parar a partir da velocidade atual:
    // d_brake = (V^2) / (2 * a)
    double brakingDistance = (currentSpeed * currentSpeed) / (2.0 * prefManager.decelerationMM);

    if (errorAbs <= brakingDistance) {
      // Fase de Desaceleração Progressiva
      currentSpeed = max(10.0, currentSpeed - (prefManager.decelerationMM * dt));
    } else {
      // Fase de Aceleração Progressiva
      currentSpeed = min(prefManager.maxSpeedMM, currentSpeed + (prefManager.accelerationMM * dt));
    }

    // Converte a velocidade linear de mm/s para frequência de passos do motor:
    // Passos/s = mm/s * passos/mm
    double stepsPerSecond = currentSpeed * STEPS_PER_MM;
    if (stepsPerSecond <= 0.0) return;

    unsigned long stepIntervalMicros = (unsigned long)(1000000.0 / stepsPerSecond);

    // Geração assíncrona e não bloqueante de pulsos baseada em micros()
    if (now - lastStepTime >= stepIntervalMicros) {
      lastStepTime = now;

      // Gera o pulso com 2us de duração (ideal para acopladores ópticos do TB6600)
      digitalWrite(STEP_PIN, HIGH);
      delayMicroseconds(2);
      digitalWrite(STEP_PIN, LOW);

      // Sincroniza a posição teórica do motor
      if (subindo) {
        currentPosition++;
      } else {
        currentPosition--;
      }
    }
  }

  void runHomingRoutine() {
    unsigned long now = micros();
    // No Homing, move lentamente na direção de descida (DIR_PIN = LOW)
    // Velocidade de homing constante e segura: 15 mm/s
    double homingSpeed = 15.0;
    double stepsPerSecond = homingSpeed * STEPS_PER_MM;
    unsigned long stepIntervalMicros = (unsigned long)(1000000.0 / stepsPerSecond);

    if (digitalRead(SENSOR_HOME) == HIGH) {
      // Ainda não acionou o sensor
      if (now - lastStepTime >= stepIntervalMicros) {
        lastStepTime = now;
        digitalWrite(DIR_PIN, LOW); // Sentido Descida
        digitalWrite(STEP_PIN, HIGH);
        delayMicroseconds(2);
        digitalWrite(STEP_PIN, LOW);
        currentPosition--;
      }
    } else {
      // SENSOR HOME ACIONADO!
      // Zera instantaneamente todas as referências do sistema em malha fechada
      noInterrupts();
      encoder.encoderCount = 0;
      interrupts();

      currentPosition = 0;
      targetPosMM = 0.0;
      isHoming = false;
      isCalibrated = true;
      currentSpeed = 0.0;

      Serial.println("🏆 HOMING REALIZADO! Origem absoluta estabelecida.");
    }
  }

  // Monitor de segurança para perda de passos
  void monitorSafety() {
    if (!USAR_ENCODER) return; // Se não usar encoder, ignora monitoramento físico de segurança
    if (!isCalibrated || isHoming || encoder.encoderError) return;

    double encoderPosMM = encoder.getPositionMM();
    double currentPosMM = (double)currentPosition / STEPS_PER_MM;

    double error = abs(currentPosMM - encoderPosMM);
    if (error > MAX_ENCODER_ERROR_MM) {
      encoder.encoderError = true;
      stop();
      // O motor continua sob retenção magnética do driver físico (que permanece energizado)
      // para segurar e travar o guincho/elevador no ar e não deixá-lo despencar!
      Serial.print("🚨 DESENCONTRO DETECTADO! Erro de ");
      Serial.print(error);
      Serial.println(" mm. Motor mantido travado sob retenção.");
    }
  }
};

extern MotorController motorController;

#endif // MOTOR_CONTROLLER_H