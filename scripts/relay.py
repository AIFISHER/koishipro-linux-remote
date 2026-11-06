#!/usr/bin/env python3
"""Transparent TCP relay: 127.0.0.1:7835 -> bore.pub:7835.

bore's own socket can't reach the bore server directly under some
sandboxed / restricted networks, but plain Python sockets can, so bore
is pointed at this relay with `bore local <port> --to 127.0.0.1`.
"""
import socket
import threading

LISTEN = ("127.0.0.1", 7835)
TARGET = ("bore.pub", 7835)


def pump(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        try:
            dst.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def handle(client):
    try:
        remote = socket.create_connection(TARGET, timeout=15)
    except OSError:
        client.close()
        return
    t1 = threading.Thread(target=pump, args=(client, remote), daemon=True)
    t2 = threading.Thread(target=pump, args=(remote, client), daemon=True)
    t1.start()
    t2.start()
    t1.join()
    t2.join()
    client.close()
    remote.close()


srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(LISTEN)
srv.listen(50)
print("relay listening on 127.0.0.1:7835 -> bore.pub:7835", flush=True)
while True:
    client, _ = srv.accept()
    threading.Thread(target=handle, args=(client,), daemon=True).start()
