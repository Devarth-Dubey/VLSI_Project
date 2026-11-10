from machine import Pin, I2C, UART, PWM
import time
import math

# ---------- UART (ESP32-CAM) ----------
uart = UART(0,115200,tx=Pin(0),rx=Pin(1))

# ---------- IMU ----------
i2c = I2C(0, scl=Pin(5), sda=Pin(4), freq=400000)
MPU_ADDR = 0x68

# wake MPU6050
i2c.writeto_mem(MPU_ADDR, 0x6B, b'\x00')

# ---------- Gyro calibration ----------
print("Calibrating gyro...")

offset = 0
for i in range(200):
    data = i2c.readfrom_mem(MPU_ADDR,0x47,2)
    val = int.from_bytes(data,'big',True)
    offset += val
    time.sleep(0.005)

offset /= 200
offset /= 131.0

print("Gyro offset:",offset)

def read_gyro_z():
    data = i2c.readfrom_mem(MPU_ADDR,0x47,2)
    val = int.from_bytes(data,'big',True)
    g = val/131.0
    g -= offset

    # noise filter
    if abs(g) < 0.2:
        g = 0

    return g

# ---------- Motors ----------
rpwm = PWM(Pin(16))
lpwm = PWM(Pin(17))
lpwm.freq(20000)
rpwm.freq(20000)

servo = PWM(Pin(15))
servo.freq(50)

def set_motor(speed):
    speed = max(-1,min(1,speed))
    if speed>0:
        rpwm.duty_u16(int(speed*65535))
        lpwm.duty_u16(0)
    elif speed<0:
        rpwm.duty_u16(0)
        lpwm.duty_u16(int(speed*65535))
        
    else:
        rpwm.duty_u16(0)
        lpwm.duty_u16(0)

def set_servo(angle):
    angle = max(0,min(180,angle))
    min_us=500
    max_us=2500
    duty=int((min_us+angle/180*(max_us-min_us))*65535/20000)
    servo.duty_u16(duty)

# ---------- Fusion ----------
yaw = 0
last_time = time.ticks_ms()
FOCAL_SCALE = 2.5

last_rx = time.ticks_ms()

while True:

    # ----- IMU integration -----
    now = time.ticks_ms()
    dt = time.ticks_diff(now,last_time)/1000
    last_time = now

    gyro_z = read_gyro_z()
    yaw += gyro_z * dt

    rotation_pixels = yaw * FOCAL_SCALE

    # ----- Vision data -----
    if uart.any():

        line = uart.readline()
         

        if line is not None:
            
            try:
                txt = line.decode().strip()
                vx,vy = map(float,txt.split(","))

                last_rx = time.ticks_ms()

                # ---- Sensor fusion ----
                obj_dx = vx - rotation_pixels
                obj_dy = vy

                speed = math.sqrt(obj_dx**2 + obj_dy**2)

                direction = math.degrees(
                    math.atan2(obj_dy,obj_dx)
                )

                # convert -180..180 → 0..180
                direction = direction + 90

                # ----- motor control -----
                if obj_dy<0:
                   motor_speed = min(speed/40,1)
                else:
                    motor_speed=-min(speed/40,1)
                set_motor(motor_speed)
                set_servo(direction)
                print(motor_speed,direction)

            except:
                pass

    # ----- failsafe -----
    if time.ticks_diff(time.ticks_ms(),last_rx) > 500:
        set_motor(0)

    time.sleep(0.01)
