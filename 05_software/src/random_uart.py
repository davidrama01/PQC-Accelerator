import secrets
import serial


PORT = "COM5"
BAUDRATE = 115200


seed = secrets.token_bytes(32)

with serial.Serial(PORT, BAUDRATE) as uart:
    uart.write(seed)
    uart.flush()

print("Semilla enviada por UART.")
