#ifndef ENCODER_MANAGER_H
#define ENCODER_MANAGER_H

#include <Arduino.h>
#include "WinchConfig.h"

class EncoderManager {
public:
  volatile long encoderCount = 0;
  volatile int lastEncoded = 0;

  bool encoderError = false;

  void begin() {
    pinMode(ENCODER_A, INPUT_PULLUP);
    pinMode(ENCODER_B, INPUT_PULLUP);

    // Inicialização da leitura inicial
    int MSB = digitalRead(ENCODER_A);
    int LSB = digitalRead(ENCODER_B);
    lastEncoded = (MSB << 1) | LSB;
  }

  void handleISR() {
    int MSB = digitalRead(ENCODER_A);
    int LSB = digitalRead(ENCODER_B);

    int encoded = (MSB << 1) | LSB;
    int sum = (lastEncoded << 2) | encoded;

    if (sum == 0b1101 || sum == 0b0100 || sum == 0b0010 || sum == 0b1011) encoderCount++;
    if (sum == 0b1110 || sum == 0b0111 || sum == 0b0001 || sum == 0b1000) encoderCount--;

    lastEncoded = encoded;
  }

  long getCount() {
    noInterrupts();
    long count = encoderCount;
    interrupts();
    return count;
  }

  void reset(long val = 0) {
    noInterrupts();
    encoderCount = val;
    interrupts();
  }

  double getPositionMM() {
    return (double)getCount() * MM_PER_ENCODER_COUNT;
  }
};

extern EncoderManager encoder;

#endif // ENCODER_MANAGER_H