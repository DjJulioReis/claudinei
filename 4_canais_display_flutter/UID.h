#ifndef UID_H
#define UID_H

#include <Arduino.h>

struct RDM_UID {
  uint16_t manufacturer_id;
  uint32_t device_id;

  RDM_UID() : manufacturer_id(0), device_id(0) {}
  RDM_UID(uint16_t man_id, uint32_t dev_id) : manufacturer_id(man_id), device_id(dev_id) {}

  bool is_equal(const RDM_UID& other) const {
    return (manufacturer_id == other.manufacturer_id) && (device_id == other.device_id);
  }

  // Verifica se o UID está contido dentro da faixa inclusive [min, max] para Discovery
  bool is_in_range(const RDM_UID& min, const RDM_UID& max) const {
    if (manufacturer_id < min.manufacturer_id || manufacturer_id > max.manufacturer_id) {
      return false;
    }
    if (manufacturer_id == min.manufacturer_id && device_id < min.device_id) {
      return false;
    }
    if (manufacturer_id == max.manufacturer_id && device_id > max.device_id) {
      return false;
    }
    return true;
  }

  // UID de All-Call (Broadcast)
  bool is_all_call() const {
    return (manufacturer_id == 0xFFFF) && (device_id == 0xFFFFFFFF);
  }
};

#endif
