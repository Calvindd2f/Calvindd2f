#!/usr/bin/python3
#parse2.py

import urllib3
from urllib.request import urlopen
from bs4 import BeautifulSoup

url = urlopen("http://192.168.92.68:8080/crawling")

page = url.read()
soup = BeautifulSoup(page, features="html.parser")

print(soup.get_text())
