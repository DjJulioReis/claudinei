#ifndef PACKETBUILDER_H
#define PACKETBUILDER_H

#include <Arduino.h>
#include "UID.h"
#include "CRC.h"

class PacketBuilder {
public:
  static size_t build_response(
    uint8_t* buffer,
    RDM_UID dest_uid,
    RDM_UID src_uid,
    uint8_t transaction_number,
    uint8_t response_type,
    uint8_t message_count,
    uint16_t sub_device,
    uint8_t command_class,
    uint16_t parameter_id,
    const uint8_t* parameter_data,
    uint8_t parameter_data_length
  ) {
    buffer[0] = 0xCC; // Start Code
    buffer[1] = 0x01; // Sub-Start Code

    uint8_t message_length = 24 + parameter_data_length;
    buffer[2] = message_length;

    // Destination UID (6 bytes)
    buffer[3] = (dest_uid.manufacturer_id >> 8) & 0xFF;
    buffer[4] = dest_uid.manufacturer_id & 0xFF;
    buffer[5] = (dest_uid.device_id >> 24) & 0xFF;
    buffer[6] = (dest_uid.device_id >> 16) & 0xFF;
    buffer[7] = (dest_uid.device_id >> 8) & 0xFF;
    buffer[8] = dest_uid.device_id & 0xFF;

    // Source UID (6 bytes)
    buffer[9] = (src_uid.manufacturer_id >> 8) & 0xFF;
    buffer[10] = src_uid.manufacturer_id & 0xFF;
    buffer[11] = (src_uid.device_id >> 24) & 0xFF;
    buffer[12] = (src_uid.device_id >> 16) & 0xFF;
    buffer[13] = (src_uid.device_id >> 8) & 0xFF;
    buffer[14] = src_uid.device_id & 0xFF;

    buffer[15] = transaction_number;
    buffer[16] = response_type;
    buffer[17] = message_count;
    buffer[18] = (sub_device >> 8) & 0xFF;
    buffer[19] = sub_device & 0xFF;

    buffer[20] = command_class;
    buffer[21] = (parameter_id >> 8) & 0xFF;
    buffer[22] = parameter_id & 0xFF;
    buffer[23] = parameter_data_length;

    if (parameter_data_length > 0 && parameter_data != NULL) {
      memcpy(&buffer[24], parameter_data, parameter_data_length);
    }

    // Calcula e anexa Checksum de 16 bits (soma de todos os bytes)
    uint16_t checksum = CRC::calculate_checksum(buffer, message_length);
    buffer[message_length] = (checksum >> 8) & 0xFF;
    buffer[message_length + 1] = checksum & 0xFF;

    return message_length + 2; // Tamanho total do pacote RDM transmitido
  }
};

#endif
