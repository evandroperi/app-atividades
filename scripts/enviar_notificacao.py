"""Envia uma notificação push para os apps (Firebase Cloud Messaging, API v1).

Uso (variáveis de ambiente): FIREBASE_SERVICE_ACCOUNT (JSON da conta de serviço),
TITULO, MENSAGEM, LINK (opcional), PUBLICO (todos | ios | android).
"""
import json
import os
import sys

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

info = json.loads(os.environ["FIREBASE_SERVICE_ACCOUNT"])
cred = service_account.Credentials.from_service_account_info(
    info, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
)
cred.refresh(Request())

titulo = os.environ["TITULO"].strip()
mensagem = os.environ["MENSAGEM"].strip()
link = os.environ.get("LINK", "").strip()
publico = os.environ.get("PUBLICO", "todos").strip() or "todos"

if link and not link.startswith("http"):
    link = "https://painel.atividadesanosiniciais.com.br/" + link.lstrip("/")

msg = {
    "topic": publico,
    "notification": {"title": titulo, "body": mensagem},
    "data": {"url": link} if link else {},
    "apns": {"payload": {"aps": {"sound": "default"}}},
    "android": {"priority": "high", "notification": {"sound": "default"}},
}

r = requests.post(
    f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send",
    headers={"Authorization": f"Bearer {cred.token}"},
    json={"message": msg},
    timeout=30,
)
print(r.status_code, r.text)
sys.exit(0 if r.ok else 1)
