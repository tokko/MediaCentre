import verisure
import os
import time
import requests
import logging

# Load credentials from secrets or environment variables
def load_credentials():
    try:
        username = os.read(os.open('/run/secrets/verisure_username', os.O_RDONLY), 1024).decode('utf-8').strip()
        password = os.read(os.open('/run/secrets/verisure_password', os.O_RDONLY), 1024).decode('utf-8').strip()
    except (FileNotFoundError, OSError):
        username = os.environ.get('USERNAME')
        password = os.environ.get('PASSWORD')
    if not username or not password:
        raise ValueError("Verisure username and password must be provided via secrets or environment variables")
    return username, password

# Configure logging
logging.basicConfig(level=logging.DEBUG)
# Initialize session
logging.debug("Logging in")
USERNAME, PASSWORD = load_credentials()
session = verisure.Session(USERNAME, PASSWORD)
# Login without Multifactor Authentication
installations = session.login()
logging.debug(f"Login done: {installations}")
# Or with Multicator Authentication, check your phone and mailbox
#session.request_mfa()
#installations = session.validate_mfa(input("code:"))

# Get the `giid` for your installation
giids = {
  inst['alias']: inst['giid']
  for inst in installations['data']['account']['installations']
}
logging.debug(f"giids: {giids}")
# {'MY STREET': '123456789000'}

logging.debug("setting giid")
# Set the giid
session.set_giid(giids["Flyttblocksvägen"])
logging.debug("giid set")
# Vacuum service endpoints
VACUUM_START_URL = "https://vacuum.granbacken/start"
VACUUM_STOP_URL = "https://vacuum.granbacken/stop"

# Long poll for state changes
last_state = None
while True:
    try:
        logging.debug("polling")
        status = session.request(session.arm_state())
        logging.debug(f"status: {status}")
        current_state = status.get('data', {}).get('installation', {}).get('armState', {}).get('statusType', 'Unknown')
        if current_state != last_state:
            logging.debug(f"Alarm status: {current_state}")
            if current_state == "ARMED_AWAY":
                requests.get(VACUUM_START_URL, verify=False)
                logging.info("Sent start cleaning request")
            elif current_state == "DISARMED":
                requests.get(VACUUM_STOP_URL, verify=False)
                logging.info("Sent stop cleaning request")
            last_state = current_state
    except Exception as e:
        logging.error(f"Error: {str(e)}")
    time.sleep(60)
