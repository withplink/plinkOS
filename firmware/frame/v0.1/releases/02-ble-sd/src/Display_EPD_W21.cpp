#include "Display_EPD_W21_spi.h"
#include "Display_EPD_W21.h"

void EPD_W21_Init(void)
{
  EPD_W21_RST_0;
  delay(10);
  EPD_W21_RST_1;
  delay(10);
}

void lcd_chkstatus(void)
{
  while(!isEPD_W21_BUSY);
}

// EPD_init — PLL=0x08. Produces ~31s waveform on hardware. Use this (EPD_USE_FAST_INIT 0).
void EPD_init(void)
{
  EPD_W21_Init();

  EPD_W21_WriteCMD(0xAA);    // CMDH
  EPD_W21_WriteDATA(0x49);
  EPD_W21_WriteDATA(0x55);
  EPD_W21_WriteDATA(0x20);
  EPD_W21_WriteDATA(0x08);
  EPD_W21_WriteDATA(0x09);
  EPD_W21_WriteDATA(0x18);

  EPD_W21_WriteCMD(PWRR);
  EPD_W21_WriteDATA(0x3F);

  EPD_W21_WriteCMD(PSR);
  EPD_W21_WriteDATA(0x5F);
  EPD_W21_WriteDATA(0x69);

  EPD_W21_WriteCMD(POFS);
  EPD_W21_WriteDATA(0x00);
  EPD_W21_WriteDATA(0x54);
  EPD_W21_WriteDATA(0x00);
  EPD_W21_WriteDATA(0x44);

  EPD_W21_WriteCMD(BTST1);
  EPD_W21_WriteDATA(0x40);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x2C);

  EPD_W21_WriteCMD(BTST2);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x17);
  EPD_W21_WriteDATA(0x49);

  EPD_W21_WriteCMD(BTST3);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x22);

  EPD_W21_WriteCMD(PLL);
  EPD_W21_WriteDATA(0x08);

  EPD_W21_WriteCMD(CDI);
  EPD_W21_WriteDATA(0x3F);

  EPD_W21_WriteCMD(TCON);
  EPD_W21_WriteDATA(0x02);
  EPD_W21_WriteDATA(0x00);

  EPD_W21_WriteCMD(TRES);
  EPD_W21_WriteDATA(0x03);
  EPD_W21_WriteDATA(0x20);
  EPD_W21_WriteDATA(0x01);
  EPD_W21_WriteDATA(0xE0);

  EPD_W21_WriteCMD(T_VDCS);
  EPD_W21_WriteDATA(0x01);

  EPD_W21_WriteCMD(PWS);
  EPD_W21_WriteDATA(0x2F);

  EPD_W21_WriteCMD(0x04);    // PON
  lcd_chkstatus();
}

// EPD_init_fast — PLL=0x02. Produces ~36s waveform on hardware (slower despite name).
void EPD_init_fast(void)
{
  EPD_W21_Init();

  EPD_W21_WriteCMD(0xAA);    // CMDH
  EPD_W21_WriteDATA(0x49);
  EPD_W21_WriteDATA(0x55);
  EPD_W21_WriteDATA(0x20);
  EPD_W21_WriteDATA(0x08);
  EPD_W21_WriteDATA(0x09);
  EPD_W21_WriteDATA(0x18);

  EPD_W21_WriteCMD(PWRR);
  EPD_W21_WriteDATA(0x3F);
  EPD_W21_WriteDATA(0x00);
  EPD_W21_WriteDATA(0x32);
  EPD_W21_WriteDATA(0x2A);
  EPD_W21_WriteDATA(0x0E);
  EPD_W21_WriteDATA(0x2A);

  EPD_W21_WriteCMD(PSR);
  EPD_W21_WriteDATA(0x5F);
  EPD_W21_WriteDATA(0x69);

  EPD_W21_WriteCMD(POFS);
  EPD_W21_WriteDATA(0x00);
  EPD_W21_WriteDATA(0x54);
  EPD_W21_WriteDATA(0x00);
  EPD_W21_WriteDATA(0x44);

  EPD_W21_WriteCMD(BTST1);
  EPD_W21_WriteDATA(0x40);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x2C);

  EPD_W21_WriteCMD(BTST2);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x16);
  EPD_W21_WriteDATA(0x25);

  EPD_W21_WriteCMD(BTST3);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x22);

  EPD_W21_WriteCMD(0x13);    // IPC
  EPD_W21_WriteDATA(0x00);
  EPD_W21_WriteDATA(0x04);

  EPD_W21_WriteCMD(PLL);
  EPD_W21_WriteDATA(0x02);

  EPD_W21_WriteCMD(0x41);    // TSE
  EPD_W21_WriteDATA(0x00);

  EPD_W21_WriteCMD(CDI);
  EPD_W21_WriteDATA(0x3F);

  EPD_W21_WriteCMD(TCON);
  EPD_W21_WriteDATA(0x02);
  EPD_W21_WriteDATA(0x00);

  EPD_W21_WriteCMD(TRES);
  EPD_W21_WriteDATA(0x03);
  EPD_W21_WriteDATA(0x20);
  EPD_W21_WriteDATA(0x01);
  EPD_W21_WriteDATA(0xE0);

  EPD_W21_WriteCMD(VDCS);
  EPD_W21_WriteDATA(0x1E);

  EPD_W21_WriteCMD(T_VDCS);
  EPD_W21_WriteDATA(0x01);

  EPD_W21_WriteCMD(0x86);    // AGID
  EPD_W21_WriteDATA(0x00);

  EPD_W21_WriteCMD(PWS);
  EPD_W21_WriteDATA(0x2F);

  EPD_W21_WriteCMD(0xE0);    // CCSET
  EPD_W21_WriteDATA(0x00);

  EPD_W21_WriteCMD(0xE6);    // TSSET
  EPD_W21_WriteDATA(0x00);

  EPD_W21_WriteCMD(0x04);    // PON
  lcd_chkstatus();
}

void EPD_sleep(void)
{
  EPD_W21_WriteCMD(0x02);    // POF
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
}

// Maps raw framebuffer token to 4-bit ACeP color code.
// Input tokens match the Color_get switch cases.
static unsigned char Color_get(unsigned char color)
{
  switch(color) {
    case 0x00: return 0x00;  // Black
    case 0xff: return 0x01;  // White
    case 0xfc: return 0x02;  // Yellow
    case 0xE0: return 0x03;  // Red
    case 0x03: return 0x05;  // Blue
    case 0x1c: return 0x06;  // Green
    default:   return 0x00;  // Unknown → black
  }
}

// Send 800×480 pixel buffer to display and trigger refresh.
// picData: 480 rows × 800 columns, 1 byte/pixel using Color_get token values.
void PIC_display(const unsigned char* picData)
{
  unsigned int i, j, k;
  unsigned char temp1, temp2, data;

  EPD_W21_WriteCMD(0x10);
  for(i = 0; i < 480; i++) {
    k = 0;
    for(j = 0; j < 800/2; j++) {
      temp1 = picData[i*800 + k++];
      temp2 = picData[i*800 + k++];
      data = (Color_get(temp1) << 4) | Color_get(temp2);
      EPD_W21_WriteDATA(data);
    }
  }

  EPD_W21_WriteCMD(0x12);    // DRF
  EPD_W21_WriteDATA(0x00);
  delay(1);                  // ≥200µs required before checking BUSY
  lcd_chkstatus();
}

void PIC_display_Clear(void)
{
  unsigned int i, j;
  EPD_W21_WriteCMD(0x10);
  for(i = 0; i < 480; i++) {
    for(j = 0; j < 800/2; j++) {
      EPD_W21_WriteDATA(White);
    }
  }
  EPD_W21_WriteCMD(0x12);    // DRF
  EPD_W21_WriteDATA(0x00);
  delay(1);
  lcd_chkstatus();
}

void EPD_Display_White(void)
{
  unsigned long i;
  EPD_W21_WriteCMD(DTM);
  for(i = 0; i < 192000; i++) {
    EPD_W21_WriteDATA(0x11);
  }
  EPD_W21_WriteCMD(PON);
  lcd_chkstatus();
  EPD_W21_WriteCMD(BTST2);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x17);
  EPD_W21_WriteDATA(0x49);
  EPD_W21_WriteCMD(DRF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
  EPD_W21_WriteCMD(POF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
}

void EPD_Display_Black(void)
{
  unsigned long i;
  EPD_W21_WriteCMD(DTM);
  for(i = 0; i < 192000; i++) {
    EPD_W21_WriteDATA(0x00);
  }
  EPD_W21_WriteCMD(PON);
  lcd_chkstatus();
  EPD_W21_WriteCMD(BTST2);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x17);
  EPD_W21_WriteDATA(0x49);
  EPD_W21_WriteCMD(DRF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
  EPD_W21_WriteCMD(POF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
}

void EPD_Display_red(void)
{
  unsigned long i;
  EPD_W21_WriteCMD(DTM);
  for(i = 0; i < 192000; i++) {
    EPD_W21_WriteDATA(0x33);
  }
  EPD_W21_WriteCMD(PON);
  lcd_chkstatus();
  EPD_W21_WriteCMD(BTST2);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x17);
  EPD_W21_WriteDATA(0x49);
  EPD_W21_WriteCMD(DRF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
  EPD_W21_WriteCMD(POF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
}

void EPD_Display_Yellow(void)
{
  unsigned long i;
  EPD_W21_WriteCMD(DTM);
  for(i = 0; i < 192000; i++) {
    EPD_W21_WriteDATA(0x22);
  }
  EPD_W21_WriteCMD(PON);
  lcd_chkstatus();
  EPD_W21_WriteCMD(BTST2);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x17);
  EPD_W21_WriteDATA(0x49);
  EPD_W21_WriteCMD(DRF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
  EPD_W21_WriteCMD(POF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
}

void EPD_Display_blue(void)
{
  unsigned long i;
  EPD_W21_WriteCMD(DTM);
  for(i = 0; i < 192000; i++) {
    EPD_W21_WriteDATA(0x55);
  }
  EPD_W21_WriteCMD(PON);
  lcd_chkstatus();
  EPD_W21_WriteCMD(BTST2);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x17);
  EPD_W21_WriteDATA(0x49);
  EPD_W21_WriteCMD(DRF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
  EPD_W21_WriteCMD(POF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
}

void EPD_Display_Green(void)
{
  unsigned long i;
  EPD_W21_WriteCMD(DTM);
  for(i = 0; i < 192000; i++) {
    EPD_W21_WriteDATA(0x66);
  }
  EPD_W21_WriteCMD(PON);
  lcd_chkstatus();
  EPD_W21_WriteCMD(BTST2);
  EPD_W21_WriteDATA(0x6F);
  EPD_W21_WriteDATA(0x1F);
  EPD_W21_WriteDATA(0x17);
  EPD_W21_WriteDATA(0x49);
  EPD_W21_WriteCMD(DRF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
  EPD_W21_WriteCMD(POF);
  EPD_W21_WriteDATA(0x00);
  lcd_chkstatus();
}
