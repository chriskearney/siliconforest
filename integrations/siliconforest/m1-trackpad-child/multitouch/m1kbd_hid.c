/* Original bounded metadata validation; source facts in ADAPTER.md. */
#include "m1kbd_hid.h"
#include <string.h>
static uint16_t u16(const uint8_t *p) { return (uint16_t)(p[0]|(unsigned)p[1]<<8); }
int m1kbd_device_metadata_header(const uint8_t *p, size_t n, struct m1kbd_device_metadata *out)
{
    if (!out) return 0;
    memset(out,0,sizeof(*out));
    if (!p || n<24 || n>DLSP_MESSAGE_BYTES-10) return 0;
    for (unsigned i=0;i<12;i++) out->words[i]=u16(p+2*i);
    return 1;
}
int m1kbd_interface_metadata_header(const uint8_t *p, size_t n, struct m1kbd_interface_metadata *out)
{
    if (!out) return 0;
    memset(out,0,sizeof(*out));
    if (!p || n<16 || n>DLSP_MESSAGE_BYTES-10) return 0;
    for (unsigned i=0;i<6;i++) out->prefix[i]=p[i];
    for (unsigned i=0;i<5;i++) out->words[i]=u16(p+6+2*i);
    return 1;
}
int m1kbd_device_info(const uint8_t *p, size_t n, uint16_t expected_product, struct m1kbd_identity *out)
{
    if (!p || !out) return M1KBD_META_ARGUMENT;
    if (n<24 || n>DLSP_MESSAGE_BYTES-10) return M1KBD_META_LENGTH;
    /* Pinned Linux requires >=3 and clamps only its enumeration loop above
     * four. We never iterate/allocate from this count: only interface 1 is
     * requested. Optional strings are unused, so no span is dereferenced. */
    if (u16(p+4)<3) return M1KBD_META_COUNT;
    if (u16(p+6)!=0x05ac) return M1KBD_META_VENDOR;
    if (!expected_product || u16(p+8)!=expected_product) return M1KBD_META_PRODUCT;
    struct m1kbd_identity result;
    memset(&result,0,sizeof(result));
    result.vendor=u16(p+6); result.product=u16(p+8); result.version=u16(p+10);
    *out=result;
    return 0;
}
int m1kbd_interface_info(const uint8_t *p, size_t n, struct m1kbd_identity *out)
{
    if (!p || !out) return M1KBD_META_ARGUMENT;
    if (n<16 || n>DLSP_MESSAGE_BYTES-10) return M1KBD_META_LENGTH;
    if (p[1]!=1) return M1KBD_META_INTERFACE;
    if (!u16(p+6) || u16(p+6)>DLSP_MESSAGE_BYTES-10) return M1KBD_META_INPUT_SIZE;
    out->max_input=u16(p+6); out->country=p[5];
    return 0;
}
int m1kbd_claim_request(uint8_t *used, uint8_t report, uint8_t subdevice)
{
    uint8_t bit;
    if (!used || (*used & ~7u)) return 0;
    if (report==0x01 && subdevice==0xd0) bit=1;
    else if (report==0x02 && subdevice==0x01) bit=2;
    else if (report==0x10 && subdevice==0x01) bit=4;
    else return 0;
    if (*used & bit) return 0;
    *used|=bit;
    return 1;
}
int m1kbd_response_matches(const struct dlsp_message *m, uint8_t report, uint8_t subdevice)
{
    return m && m->device==0xd0 && m->flags==0x40 && m->command==0x20 &&
        m->report==report && m->subdevice==subdevice;
}
int m1kbd_keyboard_input(const struct dlsp_message *m, uint16_t maximum)
{
    if (!m) return -1;
    if (m->device!=1 || m->flags!=0x20 || m->command!=0x10) return 0;
    if (!m->payload || !m->payload_length || !maximum || maximum>DLSP_MESSAGE_BYTES-10 ||
        m->payload_length>maximum) return -1;
    return 1;
}
void m1kbd_observe(const uint8_t *p, size_t n, const struct dlsp_message *m,
                   unsigned error, struct m1kbd_observation *out)
{
    if (!out) return;
    memset(out,0,sizeof(*out)); out->parser_error=error;
    if (p && n==DLSP_PACKET_BYTES) {
        out->packet_available=1; out->packet_flags=p[0]; out->packet_device=p[1];
        out->offset=u16(p+2); out->remain=u16(p+4); out->length=u16(p+6);
    }
    if (m) {
        out->message_available=1; out->device=m->device; out->flags=m->flags;
        out->command=m->command; out->report=m->report; out->subdevice=m->subdevice;
        out->id=m->id; out->response_length=m->response_length;
        out->payload_length=(uint32_t)m->payload_length;
    }
}
