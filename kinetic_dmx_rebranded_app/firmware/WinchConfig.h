#ifndef WINCH_CONFIG_H
#define WINCH_CONFIG_H

#include <Arduino.h>
#include "esp_mac.h"

// --- CONFIGURAÇÕES DE TELA OLED ---
#define LARGURA_TELA 128
#define ALTURA_TELA  64
#define OLED_RESET   -1

// --- MODO DE OPERAÇÃO: ENCODER ---
#define USAR_ENCODER  false // Defina como true para Malha Fechada ou false para Malha Aberta (ideal para testes de bancada)

// --- UUIDs DO PROTOCOLO BLE NORDIC UART ---
#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define TX_UUID      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define RX_UUID      "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

// --- PINOUT DO ESP32-C3 SUPER MINI ---
#define STEP_PIN      0  // Sinal de Passo do Driver (TB6600)
#define DIR_PIN       1  // Sinal de Direção do Driver (TB6600)
#define SENSOR_HOME   3  // Sensor óptico/fim de curso de calibração

#define ENCODER_A     4  // Canal A do Encoder de quadratura (PULLUP)
#define ENCODER_B     5  // Canal B do Encoder de quadratura (PULLUP)

#define ENC_CLK       6  // CLK do Rotary Encoder
#define ENC_DT        7  // DT do Rotary Encoder
#define ENC_SW       10  // SW do Rotary Encoder

// --- PARÂMETROS MECÂNICOS DO SISTEMA ---
#define MOTOR_STEPS_PER_REV 200.0
#define DRIVER_MICROSTEP    8.0  // Configuração 1/8 no TB6600 (1600 passos/rev)
#define REDUCTION_RATIO     6.0  // Redução mecânica de 6:1

#define ENCODER_PULSES      25.0 // 25 pulsos por volta da polia pequena
#define QUADRATURE_FACTOR   4.0  // Leitura x4

#define DRUM_DIAMETER       170.0 // mm
#define PULLEY_DIAMETER     80.0  // mm
#define PI_CONST            3.141592653589793

// --- CÁLCULO AUTOMÁTICO DE RELAÇÕES LINEARES ---
const double DRUM_CIRCUMFERENCE = DRUM_DIAMETER * PI_CONST;
const double STEPS_PER_MM = (MOTOR_STEPS_PER_REV * DRIVER_MICROSTEP * REDUCTION_RATIO) / DRUM_CIRCUMFERENCE;
const double MM_PER_PULLEY_REV = (PULLEY_DIAMETER * PI_CONST) / REDUCTION_RATIO;
const double MM_PER_ENCODER_COUNT = MM_PER_PULLEY_REV / (ENCODER_PULSES * QUADRATURE_FACTOR);

// --- PARÂMETROS DE SEGURANÇA E TOLERÂNCIA ---
#define MAX_ENCODER_ERROR_MM 50.0  // 50 mm de tolerância para erro de perda de passos
#define POSITION_TOLERANCE_MM 1.5   // Tolerância de 1.5mm
#define MAX_ALTURA_CABO_MM    3000.0 // Configurado para 3000 mm (3.0 metros) de curso útil máximo!

#endif // WINCH_CONFIG_H