import verisure
import os
import time
import requests
import logging

# Configure logging
logging.basicConfig(level=logging.DEBUG)

# Load credentials from secrets
def load_credentials():
    try:
        username = os.read(os.open('/run/secrets/verisure_username', os.O_RDONLY), 1024).decode('utf-8').strip()
        password = os.read(os.open('/run/secrets/verisure_password', os.O_RDONLY), 1024).decode('utf-8').strip()
        logging.debug(f"Loaded credentials: username={username[:3]}..., password={'*' * len(password)}")
    except (FileNotFoundError, OSError) as e:
        logging.error(f"Failed to load secrets: {str(e)}")
        raise ValueError("Verisure username and password must be provided via secrets")
    return username, password

# Initialize Verisure session
def initialize_session(username, password):
    session = verisure.Session(username, password)
    installations = session.login()
    logging.debug(f"Login successful: {installations}")
    giids = {
        inst['alias']: inst['giid']
        for inst in installations['data']['account']['installations']
    }
    logging.debug(f"giids: {giids}")
    session.set_giid(giids["Flyttblocksvägen"])
    logging.debug("giid set to Flyttblocksvägen")
    return session

# Vacuum service endpoints
VACUUM_START_URL = "http://vacuum.local/start"
VACUUM_STOP_URL = "http://vacuum.local/stop"

# Main polling loop
def main():
    username, password = load_credentials()
    session = initialize_session(username, password)
    
    while True:
        try:
            logging.debug("Polling Verisure API")
            status = session.request(session.arm_state())
            logging.debug(f"Status: {status}")
            current_state = status.get('data', {}).get('installation', {}).get('armState', {}).get('statusType', 'Unknown')
            logging.debug(f"Alarm status: {current_state}")
            
            if current_state == "ARMED_AWAY":
                requests.get(VACUUM_START_URL, verify=False, timeout=5)
                logging.info("Sent start cleaning request")
            elif current_state == "DISARMED":
                requests.get(VACUUM_STOP_URL, verify=False, timeout=5)
                logging.info("Sent stop cleaning request")
                
        except verisure.session.LoginError as e:
            logging.error(f"Session expired (LoginError): {str(e)}")
            logging.debug("Attempting to refresh session")
            try:
                session = initialize_session(username, password)
                logging.info("Session refreshed successfully")
            except verisure.session.LoginError as re:
                logging.error(f"Failed to refresh session: {str(re)}")
                time.sleep(60)  # Wait before retrying
                continue
        except requests.exceptions.RequestException as e:
            logging.error(f"Network error while sending vacuum command: {str(e)}")
        except Exception as e:
            logging.error(f"Unexpected error while polling: {str(e)}")
        
        time.sleep(60*2)

if __name__ == "__main__":
    main()
