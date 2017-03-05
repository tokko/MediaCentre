#!/bin/usr/python
from BaseHTTPServer import BaseHTTPRequestHandler,HTTPServer
from subprocess import call

class Handler(BaseHTTPRequestHandler):
	def do_GET(self):
		self.send_response(200)
		self.send_header('Content-type','text/html')
		self.end_headers()
		self.wfile.write("Hello World !")
		call(["bash", "/opt/steamstream/steamstream.sh"])
		return

PORT = 7070

httpd = HTTPServer(("", PORT), Handler)

print "serving at port", PORT
httpd.serve_forever()
