#!/usr/bin/python3
#web-client2.py

import requests

url = 'http://192.168.62.68:8080/basic-post'

info = {'offsec': 'offsec'}
post = requests.post("http://192.168.62.68:8080/basic-post/index.php", data = info)
print(post.text)
