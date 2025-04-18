import verisure
import os

USERNAME = os.environ["USERNAME"]
PASSWORD = os.environ["PASSWORD"]

session = verisure.Session(USERNAME, PASSWORD)

# Login without Multifactor Authentication
installations = session.login()
# Or with Multicator Authentication, check your phone and mailbox
#session.request_mfa()
#installations = session.validate_mfa(input("code:"))

# Get the `giid` for your installation
giids = {
  inst['alias']: inst['giid']
  for inst in installations['data']['account']['installations']
}
print(giids)
# {'MY STREET': '123456789000'}

# Set the giid
session.set_giid(giids["Flyttblocksvägen"])
arm_state = session.request(session.arm_state())
print(arm_state)
