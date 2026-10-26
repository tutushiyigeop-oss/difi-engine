#include "protocol.h"
#include <string.h>

uint32_t sd4_get32(const uint8_t *p)
{ return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|((uint32_t)p[2]<<8)|p[3]; }
void sd4_put32(uint8_t *p,uint32_t v)
{ p[0]=(uint8_t)(v>>24);p[1]=(uint8_t)(v>>16);p[2]=(uint8_t)(v>>8);p[3]=(uint8_t)v; }
void sd4_header(uint8_t *p,uint8_t op,uint32_t session,uint32_t txid,uint32_t n,uint32_t code)
{
    memcpy(p,"SDU4",4);p[4]=4;p[5]=op;p[6]=0;p[7]=0;
    sd4_put32(p+8,session);sd4_put32(p+12,txid);
    sd4_put32(p+16,n);sd4_put32(p+20,code);
}
int sd4_decode(const uint8_t *p,size_t n,sd4_frame *f)
{
    if(n<SD4_HEADER || memcmp(p,"SDU4",4))return SD4_BAD_FRAME;
    f->op=p[5];f->session=sd4_get32(p+8);f->txid=sd4_get32(p+12);
    f->length=sd4_get32(p+16);f->code=sd4_get32(p+20);f->payload=p+SD4_HEADER;
    if(p[4]!=4)return SD4_BAD_VERSION;
    if(p[6]||p[7]||f->code)return SD4_BAD_FLAGS;
    if(f->length>SD4_MAX_PAYLOAD || n!=SD4_HEADER+f->length)return SD4_BAD_LENGTH;
    if(!f->session)return SD4_BAD_SESSION;
    if(!f->txid)return SD4_BAD_TXID;
    if(f->op<SD4_CAPS || f->op>SD4_CLOSE)return SD4_BAD_OPERATION;
    switch(f->op){
    case SD4_CONFIG:if(f->length!=SD4_CONFIG_BYTES)return SD4_BAD_LENGTH;break;
    case SD4_UTC:if(f->length!=8)return SD4_BAD_LENGTH;break;
    case SD4_TX:if(f->length<4 || f->length>1024 || f->length%4)return SD4_BAD_LENGTH;break;
    case SD4_RX:if(f->length<32 || f->length%4)return SD4_BAD_LENGTH;break;
    default:if(f->length)return SD4_BAD_LENGTH;break;
    }
    return SD4_OK;
}
int sd4_config_decode(const uint8_t *p,size_t n,sd4_config *c)
{
    if(n!=SD4_CONFIG_BYTES)return SD4_BAD_LENGTH;
    c->data_sid=sd4_get32(p);c->version_sid=sd4_get32(p+4);
    c->samples=sd4_get32(p+8);c->fs=sd4_get32(p+12);c->bw=sd4_get32(p+16);
    c->rf_hz=((uint64_t)sd4_get32(p+20)<<32)|sd4_get32(p+24);
    c->rx_filter=sd4_get32(p+28);c->rx_data_sid=sd4_get32(p+32);c->rx_version_sid=sd4_get32(p+36);
    if(c->samples<1 || c->samples>256 || !c->fs || !c->bw || c->bw>c->fs ||
       c->rf_hz>SD4_RF_MAX || c->rx_filter>3)return SD4_BAD_CONFIG;
    return SD4_OK;
}
int sd4_txid_accept(uint32_t *last,uint32_t incoming)
{
    if(!incoming)return SD4_BAD_TXID;
    if(incoming<=*last)return SD4_DUPLICATE_TXID;
    *last=incoming;return SD4_OK;
}
static uint64_t pair(const uint32_t *p) {return ((uint64_t)p[0]<<32)|p[1];}
const char *sd4_validate_packet(const uint32_t *w,uint32_t n,const sd4_config *c,
                               int tx,sd4_packet_info *info)
{
    uint32_t type,base,sid,i;uint64_t bw,rf,fs;
    if(n<8 || n>SD4_MAX_WORDS)return "DIFI_WORD_COUNT";
    type=w[0]>>28;
    base=type==1?0x18600000U:type==4?0x49600000U:type==5?0x59600000U:0;
    if(!base || (w[0]&0xfff00000U)!=base || (w[0]&0xffffU)!=n)return "DIFI_HEADER";
    if((type==4 && n!=27) || (type==5 && n!=11))return "DIFI_METADATA_SIZE";
    if(w[2]!=0x006a621eU || w[3]!=(type==1?0U:type==4?1U:0x10004U))return "DIFI_CLASS_OUI";
    if(pair(w+5)>=UINT64_C(1000000000000))return "DIFI_FRACTIONAL_TIME";
    sid=type==5?c->version_sid:c->data_sid;
    if(tx && w[1]!=sid)return "TX_STREAM_ID";
    if(!tx && (c->rx_filter&(type==5?2U:1U)) &&
       w[1]!=(type==5?c->rx_version_sid:c->rx_data_sid))return "RX_FILTER_STREAM_ID";
    if(type==1){
        if(n<8 || n>263 || (tx && n!=7U+c->samples))return "DATA_SAMPLE_COUNT";
    }else if(type==5){
        if((w[7]!=0x80000002U && w[7]!=2U) || w[8]!=12U || w[9]!=4U ||
           ((w[10]>>16)&511U)<1 || ((w[10]>>16)&511U)>366 ||
           (w[10]&0xffffU)!=0x400U)return "VERSION_FIELDS";
    }else{
        if((w[7]!=0xfbb98000U && w[7]!=0x7bb98000U) || w[8]!=100U ||
           w[25]!=0xa00003cfU || w[26]!=0U)return "CONTEXT_FIELDS";
        for(i=11;i<=24;++i)
            if((i<=12 || (i>=15 && i<=18) || i>=21) && w[i])return "CONTEXT_RESERVED";
        bw=pair(w+9);rf=pair(w+13);fs=pair(w+19);
        if(((bw|rf|fs)&0xfffffU) || !bw || !fs || bw>fs || (bw>>20)>UINT32_MAX ||
           (fs>>20)>UINT32_MAX || (rf>>63) || (rf>>20)>SD4_RF_MAX)return "CONTEXT_VALUES";
        if(tx && ((bw>>20)!=c->bw || (fs>>20)!=c->fs || (rf>>20)!=c->rf_hz))return "TX_CONTEXT_CONFIG";
    }
    info->type=type;info->sequence=(w[0]>>16)&15U;info->samples=type==1?n-7U:0U;info->sid=w[1];
    return NULL;
}
const char *sd4_error_name(int e)
{
    static const char *const names[]={"OK","BAD_FRAME","BAD_VERSION","BAD_FLAGS","BAD_LENGTH",
      "BAD_OPERATION","BAD_SESSION","BAD_TXID","DUPLICATE_TXID","SESSION_PEER","SESSION_BUSY",
      "NOT_OPEN","BAD_CONFIG","NOT_CONFIGURED","UTC_REQUIRED","UTC_ALREADY_SET","BAD_PACKET",
      "RX_SEQUENCE","HW_FAULT","DMA_ERROR","UDP_ERROR","SESSION_REUSED","SESSION_LIMIT","BUSY"};
    return e>=0 && (size_t)e<sizeof(names)/sizeof(names[0])?names[e]:"UNKNOWN_ERROR";
}
