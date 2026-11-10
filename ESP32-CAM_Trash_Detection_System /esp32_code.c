#include "esp_camera.h"
#include <Arduino.h>

// ===== AI Thinker ESP32-CAM pins =====
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27

#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5

#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

#define FRAME_W 160
#define FRAME_H 120

uint8_t *prev_frame = NULL;
uint8_t *curr_frame = NULL;

camera_config_t config;

void initCamera()
{
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;

  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;

  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;

  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;

  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;

  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_GRAYSCALE;

  config.frame_size = FRAMESIZE_QQVGA;
  config.fb_count = 1;

  esp_err_t err = esp_camera_init(&config);

  if (err != ESP_OK)
  {
    Serial.println("Camera init FAILED");
    while(true);
  }

  Serial.println("Camera initialized");

  sensor_t * s = esp_camera_sensor_get();
  s->set_gain_ctrl(s,0);
  s->set_exposure_ctrl(s,0);
}

// -------- block matching ----------
void blockMatch(int x,int y,float &dx,float &dy)
{
  int best_dx = 0;
  int best_dy = 0;
  int best_error = 999999;

  for(int mx=-3; mx<=3; mx++)
  {
    for(int my=-3; my<=3; my++)
    {
      int error = 0;

      for(int i=0;i<4;i++)
      {
        for(int j=0;j<4;j++)
        {
          int x1 = x+i;
          int y1 = y+j;
          int x2 = x+i+mx;
          int y2 = y+j+my;

          if(x2<0 || x2>=FRAME_W || y2<0 || y2>=FRAME_H)
            continue;

          int p1 = prev_frame[y1*FRAME_W + x1];
          int p2 = curr_frame[y2*FRAME_W + x2];

          error += abs(p1-p2);
        }
      }

      if(error < best_error)
      {
        best_error = error;
        best_dx = mx;
        best_dy = my;
      }
    }
  }

  dx += best_dx;
  dy += best_dy;
}

void setup()
{
  Serial.begin(115200);
  delay(2000);

  initCamera();

  prev_frame = (uint8_t*)malloc(FRAME_W*FRAME_H);

  if(prev_frame == NULL)
  {
    Serial.println("Memory allocation failed");
    while(true);
  }

  camera_fb_t *fb = esp_camera_fb_get();
  memcpy(prev_frame, fb->buf, FRAME_W*FRAME_H);
  esp_camera_fb_return(fb);
}

void loop()
{
  camera_fb_t *fb = esp_camera_fb_get();

  if(!fb)
  {
    Serial.println("Frame capture failed");
    return;
  }

  curr_frame = fb->buf;

  float dx = 0;
  float dy = 0;
  int samples = 0;

  for(int y=10; y<FRAME_H-10; y+=20)
  {
    for(int x=10; x<FRAME_W-10; x+=20)
    {
      blockMatch(x,y,dx,dy);
      samples++;
    }
  }

  dx /= samples;
  dy /= samples;

  Serial.print(dx);
  Serial.print(",");
  Serial.println(dy);

  memcpy(prev_frame, curr_frame, FRAME_W*FRAME_H);

  esp_camera_fb_return(fb);
}
