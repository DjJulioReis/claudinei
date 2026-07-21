#ifndef RDMMANAGER_H
#define RDMMANAGER_H

#include <Arduino.h>
#include "esp_mac.h"
#include "UID.h"
#include "CRC.h"
#include "PacketParser.h"
#include "PacketBuilder.h"
#include "DMXTiming.h"

class RDMManager {
private:
  RDM_UID _my_uid;
  bool _muted;
  bool _identifying;
  String _device_label;
  uint32_t _device_hours;
  uint32_t _lamp_hours;

  // Referência para o endereço DMX do sistema para que possamos ler/gravar de forma sincronizada
  int& _enderecoDMX;
  void (*_saveConfigCallback)();

public:
  RDMManager(int& enderecoDMX, void (*saveCallback)())
    : _muted(false), _identifying(false), _device_label("MILETO PARIS 4CH"),
      _device_hours(120), _lamp_hours(120), _enderecoDMX(enderecoDMX), _saveConfigCallback(saveCallback) {

    // Gera UID único com base no MAC do ESP32-C3
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    uint32_t dev_id = ((uint32_t)mac[2] << 24) |
                        ((uint32_t)mac[3] << 16) |
                        ((uint32_t)mac[4] << 8)  |
                        mac[5];
    _my_uid = RDM_UID(0x4D49, dev_id); // 0x4D49 = "MI" (Mileto)
  }

  RDM_UID getMyUID() const { return _my_uid; }
  bool isIdentifying() const { return _identifying; }

  // Processa pacotes RDM recebidos e retorna o tamanho da resposta (0 se não houver resposta)
  size_t processRDMPacket(const uint8_t* rx_buffer, size_t rx_len, uint8_t* tx_buffer) {
    RDMPacketData rx_packet = PacketParser::parse(rx_buffer, rx_len);
    if (!rx_packet.is_valid) return 0;

    // Verifica se o pacote é para nós ou para broadcast/all-call
    bool is_for_me = rx_packet.destination_uid.is_equal(_my_uid);
    bool is_all_call = rx_packet.destination_uid.is_all_call();

    // RDM Discovery Unique Branch especial
    if (rx_packet.command_class == 0x10 && rx_packet.parameter_id == 0x0001) { // DISC_UNIQUE_BRANCH
      if (_muted) return 0; // Se estiver em Mute, não responde à descoberta

      // Verifica se nosso UID está dentro da faixa de descoberta solicitada
      if (rx_packet.parameter_data_length >= 12) {
        RDM_UID min_uid, max_uid;
        min_uid.manufacturer_id = ((uint16_t)rx_packet.parameter_data[0] << 8) | rx_packet.parameter_data[1];
        min_uid.device_id = ((uint32_t)rx_packet.parameter_data[2] << 24) |
                            ((uint32_t)rx_packet.parameter_data[3] << 16) |
                            ((uint32_t)rx_packet.parameter_data[4] << 8)  |
                            rx_packet.parameter_data[5];

        max_uid.manufacturer_id = ((uint16_t)rx_packet.parameter_data[6] << 8) | rx_packet.parameter_data[7];
        max_uid.device_id = ((uint32_t)rx_packet.parameter_data[8] << 24) |
                            ((uint32_t)rx_packet.parameter_data[9] << 16) |
                            ((uint32_t)rx_packet.parameter_data[10] << 8) |
                            rx_packet.parameter_data[11];

        if (_my_uid.is_in_range(min_uid, max_uid)) {
          // Discovery Response: Envia preâmbulo especial de 7 a 9 bytes de 0xFE,
          // seguido por um delimitador 0xAA, e depois os 12 bytes do UID duplo-codificados
          size_t idx = 0;
          for (int i = 0; i < 7; i++) tx_buffer[idx++] = 0xFE;
          tx_buffer[idx++] = 0xAA;

          // Codificação RDM dupla para resposta de descoberta
          uint8_t uid_bytes[6];
          uid_bytes[0] = (_my_uid.manufacturer_id >> 8) & 0xFF;
          uid_bytes[1] = _my_uid.manufacturer_id & 0xFF;
          uid_bytes[2] = (_my_uid.device_id >> 24) & 0xFF;
          uid_bytes[3] = (_my_uid.device_id >> 16) & 0xFF;
          uid_bytes[4] = (_my_uid.device_id >> 8) & 0xFF;
          uid_bytes[5] = _my_uid.device_id & 0xFF;

          uint16_t checksum = 0;
          for (int i = 0; i < 6; i++) {
            tx_buffer[idx++] = uid_bytes[i] | 0xAA;
            tx_buffer[idx++] = uid_bytes[i] | 0x55;
            checksum += uid_bytes[i];
          }

          uint8_t cs_msb = (checksum >> 8) & 0xFF;
          uint8_t cs_lsb = checksum & 0xFF;

          tx_buffer[idx++] = cs_msb | 0xAA;
          tx_buffer[idx++] = cs_msb | 0x55;
          tx_buffer[idx++] = cs_lsb | 0xAA;
          tx_buffer[idx++] = cs_lsb | 0x55;

          return idx;
        }
      }
      return 0;
    }

    if (!is_for_me && !is_all_call) return 0;

    // Resposta padrão a comandos RDM GET/SET
    uint8_t response_data[231];
    uint8_t response_len = 0;
    uint8_t response_type = 0x00; // ACK

    if (rx_packet.command_class == 0x20) { // GET_COMMAND
      switch (rx_packet.parameter_id) {
        case 0x0002: // DISC_MUTE
          _muted = true;
          response_data[0] = 0x00; // Control Field MSB
          response_data[1] = 0x00; // Control Field LSB
          response_len = 2;
          break;

        case 0x0003: // DISC_UN_MUTE
          _muted = false;
          response_data[0] = 0x00;
          response_data[1] = 0x00;
          response_len = 2;
          break;

        case 0x0050: // SUPPORTED_PARAMETERS
          {
            uint16_t pids[] = {
              0x0030, 0x0050, 0x0060, 0x0080, 0x0082, 0x0083, 0x00C0, 0x00C1,
              0x00E0, 0x00E1, 0x00F0, 0x0120, 0x0200, 0x0400, 0x0401, 0x1000
            };
            response_len = sizeof(pids);
            for (size_t i = 0; i < response_len / 2; i++) {
              response_data[i * 2] = (pids[i] >> 8) & 0xFF;
              response_data[i * 2 + 1] = pids[i] & 0xFF;
            }
          }
          break;

        case 0x0060: // DEVICE_INFO
          response_data[0] = 0x01; response_data[1] = 0x00; // Protocol Version
          response_data[2] = 0x00; response_data[3] = 0x01; // Device Model description
          response_data[4] = 0x01; response_data[5] = 0x01; // Product Category (Dimmer/Pista)
          response_data[6] = 0x05; response_data[7] = 0x05; response_data[8] = 0x00; response_data[9] = 0x00; // Software Version ID
          response_data[10] = 0x00; response_data[11] = 0x04; // DMX Footprint (4 Canais)
          response_data[12] = 0x01; // DMX Personality (1)
          response_data[13] = 0x01; // DMX Personality Count (1)
          response_data[14] = (_enderecoDMX >> 8) & 0xFF;
          response_data[15] = _enderecoDMX & 0xFF; // DMX Start Address
          response_data[16] = 0x00; response_data[17] = 0x00; // Sub-Device Count
          response_data[18] = 0x01; // Sensor Count (1)
          response_len = 19;
          break;

        case 0x0080: // DEVICE_LABEL
          response_len = _device_label.length();
          memcpy(response_data, _device_label.c_str(), response_len);
          break;

        case 0x0082: // MANUFACTURER_LABEL
          {
            String man = "MILETO";
            response_len = man.length();
            memcpy(response_data, man.c_str(), response_len);
          }
          break;

        case 0x0083: // GET MODEL DESCRIPTION
          {
            String desc = "PARIS LED FLOOR 4CH";
            response_len = desc.length();
            memcpy(response_data, desc.c_str(), response_len);
          }
          break;

        case 0x00C0: // GET SOFTWARE VERSION
          {
            String soft = "v5.5.0";
            response_len = soft.length();
            memcpy(response_data, soft.c_str(), response_len);
          }
          break;

        case 0x00C1: // GET BOOT SOFTWARE VERSION
          response_data[0] = 0x01; response_data[1] = 0x00; response_data[2] = 0x00; response_data[3] = 0x00;
          response_len = 4;
          break;

        case 0x00E0: // GET DMX PERSONALITY
          response_data[0] = 0x01; // Current Personality
          response_data[1] = 0x01; // Personality Count
          response_len = 2;
          break;

        case 0x00E1: // GET DMX PERSONALITY DESCRIPTION
          response_data[0] = 0x01; // Personality Index
          response_data[1] = 0x00; response_data[2] = 0x04; // Footprint (4)
          {
            String desc = "4-Channel Dimmer";
            memcpy(&response_data[3], desc.c_str(), desc.length());
            response_len = 3 + desc.length();
          }
          break;

        case 0x00F0: // GET DMX START ADDRESS
          response_data[0] = (_enderecoDMX >> 8) & 0xFF;
          response_data[1] = _enderecoDMX & 0xFF;
          response_len = 2;
          break;

        case 0x0120: // GET SLOT INFO
          response_data[0] = 0x00; response_data[1] = 0x00; // Slot offset
          response_data[2] = 0x00; // Slot type: Intensity
          response_len = 3;
          break;

        case 0x0200: // GET SENSOR DEFINITION
          response_data[0] = 0x00; // Sensor index
          response_data[1] = 0x00; // Type: Temperature
          response_data[2] = 0x00; // Unit: Celsius
          response_data[3] = 0x00; // Prefix: None
          response_data[4] = 0x00; response_data[5] = 0x00; // Range min
          response_data[6] = 0x00; response_data[7] = 100;  // Range max
          response_len = 8;
          break;

        case 0x0030: // GET STATUS MESSAGES
          response_data[0] = 0x00; // Status type: None
          response_len = 1;
          break;

        case 0x0400: // GET DEVICE HOURS
          response_data[0] = (_device_hours >> 24) & 0xFF;
          response_data[1] = (_device_hours >> 16) & 0xFF;
          response_data[2] = (_device_hours >> 8) & 0xFF;
          response_data[3] = _device_hours & 0xFF;
          response_len = 4;
          break;

        case 0x0401: // GET LAMP HOURS
          response_data[0] = (_lamp_hours >> 24) & 0xFF;
          response_data[1] = (_lamp_hours >> 16) & 0xFF;
          response_data[2] = (_lamp_hours >> 8) & 0xFF;
          response_data[3] = _lamp_hours & 0xFF;
          response_len = 4;
          break;

        case 0x1000: // GET IDENTIFY DEVICE
          response_data[0] = _identifying ? 0x01 : 0x00;
          response_len = 1;
          break;

        default:
          response_type = 0x02; // NACK (NR_UNSUPPORTED_COMMAND_CLASS)
          response_data[0] = 0x00; response_data[1] = 0x00; // Reason
          response_len = 2;
          break;
      }
    }
    else if (rx_packet.command_class == 0x30) { // SET_COMMAND
      switch (rx_packet.parameter_id) {
        case 0x0080: // SET DEVICE LABEL
          if (rx_packet.parameter_data_length <= 32) {
            char label[33];
            memcpy(label, rx_packet.parameter_data, rx_packet.parameter_data_length);
            label[rx_packet.parameter_data_length] = '\0';
            _device_label = String(label);
            response_len = 0;
          } else {
            response_type = 0x02; // NACK
            response_data[0] = 0x00; response_data[1] = 0x04; // NR_DATA_OUT_OF_RANGE
            response_len = 2;
          }
          break;

        case 0x00F0: // SET DMX START ADDRESS
          if (rx_packet.parameter_data_length >= 2) {
            int new_addr = ((int)rx_packet.parameter_data[0] << 8) | rx_packet.parameter_data[1];
            if (new_addr >= 1 && new_addr <= 512) {
              _enderecoDMX = new_addr;
              if (_saveConfigCallback) _saveConfigCallback();
              response_len = 0;
            } else {
              response_type = 0x02; // NACK
              response_data[0] = 0x00; response_data[1] = 0x04; // NR_DATA_OUT_OF_RANGE
              response_len = 2;
            }
          }
          break;

        case 0x1000: // SET IDENTIFY DEVICE
          if (rx_packet.parameter_data_length >= 1) {
            _identifying = (rx_packet.parameter_data[0] != 0);
            response_len = 0;
          }
          break;

        default:
          response_type = 0x02; // NACK
          response_data[0] = 0x00; response_data[1] = 0x00;
          response_len = 2;
          break;
      }
    }

    // Se o comando RDM for um All-Call/Broadcast, nós executamos a ação, mas NÃO enviamos resposta física
    // para evitar colisões no barramento RS-485
    if (is_all_call) return 0;

    // Constrói a resposta RDM utilizando o PacketBuilder
    return PacketBuilder::build_response(
      tx_buffer,
      rx_packet.source_uid,
      _my_uid,
      rx_packet.transaction_number,
      response_type,
      0x00, // Message Count
      0x0000, // Sub-Device
      rx_packet.command_class + 1, // Response Command Class (ex: GET_COMMAND_RESPONSE = 0x21)
      rx_packet.parameter_id,
      response_data,
      response_len
    );
  }
};

#endif
