#ifndef DMXTIMING_H
#define DMXTIMING_H

#include <Arduino.h>

struct DMXTiming {
  uint32_t break_time_us;     // ANSI E1.11 BREAK time (padrão: 176us)
  uint32_t mab_time_us;        // ANSI E1.11 Mark After Break (padrão: 12us)
  uint32_t inter_packet_us;    // Intervalo entre pacotes DMX (padrão: 1000us)
  uint32_t last_packet_time;   // Timestamp para controle de refresh não bloqueante
};

#endif
