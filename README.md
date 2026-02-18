#gps_nmea_streamer
___________________________________
Tested on:
  Android phone: 
   - Samsung Galaxy Flips 5
     
  IOS phone:

___________________________________
WHAT IS THIS DOING?

The app turns your phone into a network-connected GPS antenna. It works in three steps:

Displays Data: Shows your real-time coordinates, speed, and heading on a clear on-screen dashboard.

Converts to NMEA: Automatically formats raw GPS data into the standard NMEA 0183 ($GPRMC) format used in marine navigation.

Streams via UDP: Sends the NMEA sentences over Wi-Fi to a chosen IP address and port. This allows software like OpenCPN or other chartplotters to use your phone's GPS as their primary location source.

___________________________________
INSTALLING GUIDE:

___________________________________
Example of the code for the receiving device:

import socket

# Settings – the port must be the same as in the application (10110)
UDP_IP = "0.0.0.0"  # Listen on all network interfaces
UDP_PORT = 10110

# Create UDP socket
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((UDP_IP, UDP_PORT))

print(f"Listening for NMEA data on port {UDP_PORT}...")
print("Press Ctrl+C to stop.\n")

try:
    while True:
        # Receive data (buffer size 1024 bytes)
        data, addr = sock.recvfrom(1024)
        
        # Convert bytes to text and print
        nmea_sentence = data.decode('utf-8').strip()
        print(f"Received from device {addr[0]}: {nmea_sentence}")
        
except KeyboardInterrupt:
    print("\nStopping listener.")
    sock.close()
