#ifndef CRC_H
#define CRC_H

#include <Arduino.h>

class CRC {
public:
  // Calcula o Checksum padrão de 16 bits para pacotes RDM (soma simples de todos os bytes)
  static uint16_t calculate_checksum(const uint8_t* buffer, size_t length) {
    uint16_t checksum = 0;
    for (size_t i = 0; i < length; i++) {
      checksum += buffer[i];
    }
    return checksum;
  }
};

#endif
