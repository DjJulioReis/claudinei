#ifndef PACKETPARSER_H
#define PACKETPARSER_H

#include <Arduino.h>
#include "UID.h"
#include "CRC.h"

struct RDMPacketData {
  bool is_valid;
  RDM_UID destination_uid;
  RDM_UID source_uid;
  uint8_t transaction_number;
  uint8_t port_id_response_type;
  uint8_t message_count;
  uint16_t sub_device;
  uint8_t command_class;
  uint16_t parameter_id;
  uint8_t parameter_data_length;
  uint8_t parameter_data[231];
};

class PacketParser {
public:
  static RDMPacketData parse(const uint8_t* buffer, size_t length) {
    RDMPacketData data;
    data.is_valid = false;

    // Pacote RDM mínimo tem 26 bytes (24 bytes de cabeçalho + 2 bytes de checksum)
    if (length < 26) return data;
    if (buffer[0] != 0xCC || buffer[1] != 0x01) return data;

    uint8_t message_length = buffer[2];
    if (length < (size_t)(message_length + 2)) return data;

    // Validação de Checksum
    uint16_t calc_cs = CRC::calculate_checksum(buffer, message_length);
    uint16_t rx_cs = ((uint16_t)buffer[message_length] << 8) | buffer[message_length + 1];
    if (calc_cs != rx_cs) return data;

    // Extrai UIDs de Destino e Origem
    uint16_t dest_man = ((uint16_t)buffer[3] << 8) | buffer[4];
    uint32_t dest_dev = ((uint32_t)buffer[5] << 24) |
                        ((uint32_t)buffer[6] << 16) |
                        ((uint32_t)buffer[7] << 8)  |
                        buffer[8];
    data.destination_uid = RDM_UID(dest_man, dest_dev);

    uint16_t src_man = ((uint16_t)buffer[9] << 8) | buffer[10];
    uint32_t src_dev = ((uint32_t)buffer[11] << 24) |
                       ((uint32_t)buffer[12] << 16) |
                       ((uint32_t)buffer[13] << 8)  |
                       buffer[14];
    data.source_uid = RDM_UID(src_man, src_dev);

    data.transaction_number = buffer[15];
    data.port_id_response_type = buffer[16];
    data.message_count = buffer[17];
    data.sub_device = ((uint16_t)buffer[18] << 8) | buffer[19];
    data.command_class = buffer[20];
    data.parameter_id = ((uint16_t)buffer[21] << 8) | buffer[22];

    data.parameter_data_length = buffer[23];
    if (data.parameter_data_length > 0) {
      memcpy(data.parameter_data, &buffer[24], data.parameter_data_length);
    }

    data.is_valid = true;
    return data;
  }
};

#endif
