#include "protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static sd4_config config={0x12345678U,0x87654321U,256,20000000,10000000,UINT64_C(100000000),3,0x12345678U,0x87654321U};
static void pair(uint32_t *p,uint64_t v){p[0]=(uint32_t)(v>>32);p[1]=(uint32_t)v;}
static void data_packet(uint32_t *w,uint32_t samples,uint32_t seq)
{
    uint32_t i;memset(w,0,SD4_MAX_PAYLOAD);
    w[0]=0x18600000U|(seq<<16)|(7U+samples);w[1]=config.data_sid;w[2]=0x6a621eU;
    w[4]=1792880000U;pair(w+5,UINT64_C(999999999999));
    for(i=0;i<samples;++i)w[7U+i]=0x7fff8000U^i;
}
static void context_packet(uint32_t *w)
{
    memset(w,0,SD4_MAX_PAYLOAD);w[0]=0x496f001bU;w[1]=config.data_sid;w[2]=0x6a621eU;w[3]=1;
    w[7]=0xfbb98000U;w[8]=100;pair(w+9,(uint64_t)config.bw<<20);
    pair(w+13,config.rf_hz<<20);pair(w+19,(uint64_t)config.fs<<20);w[25]=0xa00003cfU;
}
static void version_packet(uint32_t *w)
{
    memset(w,0,SD4_MAX_PAYLOAD);w[0]=0x5967000bU;w[1]=config.version_sid;w[2]=0x6a621eU;w[3]=0x10004;
    w[7]=0x80000002;w[8]=12;w[9]=4;w[10]=(26U<<25)|(298U<<16)|0x400U;
}
static void test_wire(void)
{
    uint8_t bytes[SD4_MAX_FRAME]={0};sd4_frame f;uint32_t value=0;
    sd4_header(bytes,SD4_OPEN,0xaabbccdd,0x12345678,0,0);
    assert(!memcmp(bytes,"SDU4\x04\x02\x00\x00\xaa\xbb\xcc\xdd\x12\x34\x56\x78",16));
    assert(sd4_decode(bytes,24,&f)==0 && f.session==0xaabbccdd && f.txid==0x12345678);
    assert(sd4_decode(bytes,23,&f)==SD4_BAD_FRAME);
    bytes[4]=3;assert(sd4_decode(bytes,24,&f)==SD4_BAD_VERSION);bytes[4]=4;
    bytes[7]=1;assert(sd4_decode(bytes,24,&f)==SD4_BAD_FLAGS);bytes[7]=0;
    sd4_put32(bytes+20,1);assert(sd4_decode(bytes,24,&f)==SD4_BAD_FLAGS);sd4_put32(bytes+20,0);
    sd4_put32(bytes+16,4);assert(sd4_decode(bytes,24,&f)==SD4_BAD_LENGTH);
    sd4_header(bytes,SD4_TX,1,1,4,0);assert(sd4_decode(bytes,28,&f)==0);
    sd4_header(bytes,SD4_TX,1,1,1024,0);assert(sd4_decode(bytes,1048,&f)==0);
    sd4_header(bytes,SD4_TX,1,1,1028,0);assert(sd4_decode(bytes,1052,&f)==SD4_BAD_LENGTH);
    sd4_header(bytes,SD4_RX,1,1,1052,0);assert(sd4_decode(bytes,1076,&f)==0);
    sd4_header(bytes,SD4_RX,1,1,1056,0);assert(sd4_decode(bytes,1080,&f)==SD4_BAD_LENGTH);
    sd4_header(bytes,SD4_OPEN,0,1,0,0);assert(sd4_decode(bytes,24,&f)==SD4_BAD_SESSION);
    sd4_header(bytes,SD4_OPEN,1,0,0,0);assert(sd4_decode(bytes,24,&f)==SD4_BAD_TXID);
    assert(sd4_txid_accept(&value,1)==0 && value==1);
    assert(sd4_txid_accept(&value,1)==SD4_DUPLICATE_TXID && value==1);
    assert(sd4_txid_accept(&value,0)==SD4_BAD_TXID);
    assert(sd4_txid_accept(&value,UINT32_MAX)==0);
    assert(sd4_txid_accept(&value,1)==SD4_DUPLICATE_TXID); /* wrap is forbidden */
}
static void test_config(void)
{
    uint8_t p[40];sd4_config c;
    sd4_put32(p,config.data_sid);sd4_put32(p+4,config.version_sid);sd4_put32(p+8,256);
    sd4_put32(p+12,20000000);sd4_put32(p+16,10000000);sd4_put32(p+20,23);sd4_put32(p+24,1215752192U);
    sd4_put32(p+28,3);sd4_put32(p+32,config.rx_data_sid);sd4_put32(p+36,config.rx_version_sid);
    assert(sd4_config_decode(p,40,&c)==0 && c.rf_hz==SD4_RF_MAX && c.rx_version_sid==config.version_sid);
    assert(sd4_config_decode(p,39,&c)==SD4_BAD_LENGTH);
    sd4_put32(p+8,0);assert(sd4_config_decode(p,40,&c)==SD4_BAD_CONFIG);
    sd4_put32(p+8,257);assert(sd4_config_decode(p,40,&c)==SD4_BAD_CONFIG);
    sd4_put32(p+8,1);assert(sd4_config_decode(p,40,&c)==0);
    sd4_put32(p+12,0);assert(sd4_config_decode(p,40,&c)==SD4_BAD_CONFIG);sd4_put32(p+12,20000000);
    sd4_put32(p+16,20000001);assert(sd4_config_decode(p,40,&c)==SD4_BAD_CONFIG);sd4_put32(p+16,10000000);
    sd4_put32(p+24,1215752193U);assert(sd4_config_decode(p,40,&c)==SD4_BAD_CONFIG);sd4_put32(p+24,1215752192U);
    sd4_put32(p+28,4);assert(sd4_config_decode(p,40,&c)==SD4_BAD_CONFIG);
}
static void test_packets(void)
{
    uint32_t w[SD4_MAX_WORDS],i;sd4_packet_info info;const uint32_t sizes[]={1,2,255,256};
    for(i=0;i<4;++i){
        data_packet(w,sizes[i],15);assert(sd4_validate_packet(w,sizes[i]+7,&config,0,&info)==NULL);
        assert(info.samples==sizes[i] && info.sequence==15 && w[7]==0x7fff8000U);
    }
    data_packet(w,1,0);assert(sd4_validate_packet(w,8,&config,1,&info)!=NULL); /* TX N must equal config */
    data_packet(w,256,0);assert(sd4_validate_packet(w,263,&config,1,&info)==NULL);
    w[1]++;assert(sd4_validate_packet(w,263,&config,0,&info)!=NULL);w[1]--;
    w[3]=1;assert(sd4_validate_packet(w,263,&config,0,&info)!=NULL);w[3]=0;
    pair(w+5,UINT64_C(1000000000000));assert(sd4_validate_packet(w,263,&config,0,&info)!=NULL);
    data_packet(w,256,0);w[0]^=0x01000000;assert(sd4_validate_packet(w,263,&config,0,&info)!=NULL);
    context_packet(w);assert(sd4_validate_packet(w,27,&config,1,&info)==NULL && info.sequence==15 && info.samples==0);
    w[11]=1;assert(sd4_validate_packet(w,27,&config,0,&info)!=NULL);w[11]=0;
    w[26]=1;assert(sd4_validate_packet(w,27,&config,0,&info)!=NULL);w[26]=0;
    w[20]|=1;assert(sd4_validate_packet(w,27,&config,0,&info)!=NULL);
    context_packet(w);pair(w+9,(uint64_t)(config.fs+1)<<20);assert(sd4_validate_packet(w,27,&config,0,&info)!=NULL);
    context_packet(w);w[7]=0x7bb98000;assert(sd4_validate_packet(w,27,&config,0,&info)==NULL);
    version_packet(w);assert(sd4_validate_packet(w,11,&config,1,&info)==NULL && info.type==5 && info.sequence==7);
    w[10]&=0xfe00ffff;assert(sd4_validate_packet(w,11,&config,0,&info)!=NULL);
    version_packet(w);w[10]|=1;assert(sd4_validate_packet(w,11,&config,0,&info)!=NULL);
    version_packet(w);w[8]=0;assert(sd4_validate_packet(w,11,&config,0,&info)!=NULL);
}
int main(void)
{
    test_wire();test_config();test_packets();
    puts("PASS: SDU4 framing/endian/length, strict transaction IDs, config boundaries, 1..256 custom IQ and full metadata profiles");
    puts("HOST SOFTWARE TEST ONLY: no DMA, FPGA, UDP hardware, or board acceptance was exercised.");
    return 0;
}
