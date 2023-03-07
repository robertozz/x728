#X728 RTC setting up
sudo sed -i '$ i rtc-ds1307' /etc/modules
sudo sed -i '$ i echo ds1307 0x68 > /sys/class/i2c-adapter/i2c-1/new_device' /etc/rc.local
sudo sed -i '$ i hwclock -s' /etc/rc.local
sudo sed -i '$ i #x728 Start power management on boot' /etc/rc.local

#x728 Powering on /reboot /full shutdown through hardware
#!/bin/bash

#sudo sed -e '/shutdown/ s/^#*/#/' -i /etc/rc.local

echo '#!/bin/bash

SHUTDOWN=5
REBOOTPULSEMINIMUM=200
REBOOTPULSEMAXIMUM=600
echo "$SHUTDOWN" > /sys/class/gpio/export
echo "in" > /sys/class/gpio/gpio$SHUTDOWN/direction
BOOT=12
echo "$BOOT" > /sys/class/gpio/export
echo "out" > /sys/class/gpio/gpio$BOOT/direction
echo "1" > /sys/class/gpio/gpio$BOOT/value

echo "X728 Shutting down..."

while [ 1 ]; do
  shutdownSignal=$(cat /sys/class/gpio/gpio$SHUTDOWN/value)
  if [ $shutdownSignal = 0 ]; then
    /bin/sleep 0.2
  else
    pulseStart=$(date +%s%N | cut -b1-13)
    while [ $shutdownSignal = 1 ]; do
      /bin/sleep 0.02
      if [ $(($(date +%s%N | cut -b1-13)-$pulseStart)) -gt $REBOOTPULSEMAXIMUM ]; then
        echo "X728 Shutting down", SHUTDOWN, ", halting Rpi ..."
        sudo poweroff
        exit
      fi
      shutdownSignal=$(cat /sys/class/gpio/gpio$SHUTDOWN/value)
    done
    if [ $(($(date +%s%N | cut -b1-13)-$pulseStart)) -gt $REBOOTPULSEMINIMUM ]; then
      echo "X728 Rebooting", SHUTDOWN, ", recycling Rpi ..."
      sudo reboot
      exit
    fi
  fi
done' > /etc/x728pwr.sh
sudo chmod +x /etc/x728pwr.sh
sudo sed -i '$ i /etc/x728pwr.sh &' /etc/rc.local


#X728 full shutdown through Software
#!/bin/bash

sudo sed -e '/button/ s/^#*/#/' -i /etc/rc.local

echo '#!/bin/bash

BUTTON=13

echo "$BUTTON" > /sys/class/gpio/export;
echo "out" > /sys/class/gpio/gpio$BUTTON/direction
echo "1" > /sys/class/gpio/gpio$BUTTON/value

SLEEP=${1:-4}

re='^[0-9\.]+$'
if ! [[ $SLEEP =~ $re ]] ; then
   echo "error: sleep time not a number" >&2; exit 1
fi

echo "X728 Shutting down..."
/bin/sleep $SLEEP

#restore GPIO 13
echo "0" > /sys/class/gpio/gpio$BUTTON/value
' > /usr/local/bin/x728softsd.sh
sudo chmod +x /usr/local/bin/x728softsd.sh
sudo echo "alias x728off='sudo x728softsd.sh'" >> ~/x728/.bashrc

#X728 Battery voltage & precentage reading
#!/bin/bash

#Get current PYTHON verson, 2 or 3
PY_VERSION=`python -V 2>&1|awk '{print $2}'|awk -F '.' '{print $1}'`

#sudo sed -e '/shutdown/ s/^#*/#/' -i /etc/rc.local

echo '#!/usr/bin/env python
import struct
import smbus
import sys
import time
import RPi.GPIO as GPIO

# Global settings
# GPIO26 is for x728 V2.1/V2.2/V2.3, GPIO13 is for X728 v2.0/v1.2/v1.3
GPIO_PORT 	= 13
I2C_ADDR    = 0x36

GPIO.setmode(GPIO.BCM)
GPIO.setup(GPIO_PORT, GPIO.OUT)
GPIO.setwarnings(False)

def readVoltage(bus):

     address = I2C_ADDR
     read = bus.read_word_data(address, 2)
     swapped = struct.unpack("<H", struct.pack(">H", read))[0]
     voltage = swapped * 1.25 /1000/16
     return voltage

def readCapacity(bus):

     address = I2C_ADDR
     read = bus.read_word_data(address, 4)
     swapped = struct.unpack("<H", struct.pack(">H", read))[0]
     capacity = swapped/256
     return capacity

bus = smbus.SMBus(1) # 0 = /dev/i2c-0 (port I2C0), 1 = /dev/i2c-1 (port I2C1)
'> ~/x728/x728bat.py
if [ $PY_VERSION -eq 3 ]; then
    echo '
while True:
 print ("******************")
 print ("Voltage:%5.2fV" % readVoltage(bus))
 print ("Battery:%5i%%" % readCapacity(bus))

 if readCapacity(bus) == 100:
        print ("Battery FULL")
 if readCapacity(bus) < 20:
        print ("Battery Low")

#Set battery low voltage to shut down, you can modify the 3.00 to other value
 if readVoltage(bus) < 3.00:
                print ("Battery LOW!!!")
                print ("Shutdown in 10 seconds")
                time.sleep(10)
                GPIO.output(GPIO_PORT, GPIO.HIGH)
                time.sleep(3)
                GPIO.output(GPIO_PORT, GPIO.LOW)

 time.sleep(2)
' >> ~/x728/x728bat.py
else
    echo '
while True:
 print "******************"
 print "Voltage:%5.2fV" % readVoltage(bus)
 print "Battery:%5i%%" % readCapacity(bus)
 if readCapacity(bus) == 100:
         print "Battery FULL"
 if readCapacity(bus) < 20:
         print "Battery Low"
#Set battery low voltage to shut down, you can modify the 3.00 to other value
 if readVoltage(bus) < 3.00:
         print "Battery LOW!!!"
         print "Shutdown in 10 seconds"
         time.sleep(10)
         GPIO.output(GPIO_PORT, GPIO.HIGH)
         time.sleep(3)
         GPIO.output(GPIO_PORT, GPIO.LOW)
 time.sleep(2)
' >> ~/x728/x728bat.py
fi
sudo chmod +x ~/x728/x728bat.py

#X728 AC Power loss / power adapter failture detection
#!/bin/bash

sudo sed -e '/button/ s/^#*/#/' -i /etc/rc.local

echo '#!/usr/bin/env python
import RPi.GPIO as GPIO

GPIO.setmode(GPIO.BCM)
GPIO.setup(6, GPIO.IN)

def my_callback(channel):
    if GPIO.input(6):     # if port 6 == 1
        print "---AC Power Loss OR Power Adapter Failure---"
    else:                  # if port 6 != 1
        print "---AC Power OK,Power Adapter OK---"

GPIO.add_event_detect(6, GPIO.BOTH, callback=my_callback)

print "1.Make sure your power adapter is connected"
print "2.Disconnect and connect the power adapter to test"
print "3.When power adapter disconnected, you will see: AC Power Loss or Power Adapter Failure"
print "4.When power adapter disconnected, you will see: AC Power OK, Power Adapter OK"

raw_input("Testing Started")
' > ~/x728/x728pld.py
sudo chmod +x ~/x728/x728pld.py
