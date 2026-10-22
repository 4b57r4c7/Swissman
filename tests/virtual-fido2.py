#!/usr/bin/env python3
"""A software FIDO2 security key for tests, attached through Linux UHID.

Usage: sudo virtual-fido2.py [--hidraw-file PATH]

Creates a USB HID FIDO device (needs /dev/uhid, from the uhid kernel
module) and answers CTAP2 requests until killed. When the device is up,
the path of its hidraw node is written to PATH (default: stdout).

It implements just enough of CTAP 2.0 for systemd-cryptenroll and
systemd-cryptsetup: getInfo, makeCredential and getAssertion with the
hmac-secret extension, and the clientPIN key agreement that hmac-secret
needs (PIN/UV auth protocol 1). It has no PIN and approves user presence
on its own. Credentials only live in memory, so the process must keep
running between enrolling a disk and unlocking it.

THIS IS NOT A SECURITY KEY. Anyone with access to the machine can use it.
"""
import argparse
import glob
import hashlib
import hmac
import os
import select
import struct
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from fido2 import cbor

AAGUID = bytes.fromhex("5357495353") + bytes(11)  # "SWISS", zero padded

# CTAPHID (CTAP 2.0, section 8.1)
BROADCAST_CID = 0xFFFFFFFF
PACKET = 64
CMD_PING, CMD_MSG, CMD_INIT, CMD_WINK, CMD_CBOR, CMD_CANCEL, CMD_ERROR = (
    0x01, 0x03, 0x06, 0x08, 0x10, 0x11, 0x3F)
CAPABILITY_WINK, CAPABILITY_CBOR, CAPABILITY_NMSG = 0x01, 0x04, 0x08
ERR_INVALID_CMD = 0x01

# CTAP2 commands and status codes
MAKE_CREDENTIAL, GET_ASSERTION, GET_INFO, CLIENT_PIN = 0x01, 0x02, 0x04, 0x06
OK = 0x00
ERR_INVALID_COMMAND = 0x01
ERR_INVALID_PARAMETER = 0x02
ERR_UNSUPPORTED_ALGORITHM = 0x26
ERR_NO_CREDENTIALS = 0x2E
ERR_PIN_AUTH_INVALID = 0x33
ERR_INVALID_OPTION = 0x2C

FLAG_UP, FLAG_AT, FLAG_ED = 0x01, 0x40, 0x80
COSE_ES256 = -7
COSE_ECDH_ES_HKDF_256 = -25

# HID report descriptor of a FIDO device: usage page 0xF1D0, 64-byte
# input and output reports.
REPORT_DESCRIPTOR = bytes.fromhex(
    "06d0f1 0901 a101"
    "0920 1500 26ff00 7508 9540 8102"
    "0921 1500 26ff00 7508 9540 9102"
    "c0".replace(" ", ""))

# UHID (include/uapi/linux/uhid.h)
UHID_OUTPUT = 6
UHID_CREATE2, UHID_INPUT2 = 11, 12
UHID_EVENT_SIZE = 4 + 128 + 64 + 64 + 2 + 2 + 4 + 4 + 4 + 4 + 4096


def cose_public_key(public_key, alg):
    numbers = public_key.public_numbers()
    return {1: 2, 3: alg, -1: 1,
            -2: numbers.x.to_bytes(32, "big"), -3: numbers.y.to_bytes(32, "big")}


def public_key_from_cose(key):
    point = b"\x04" + key[-2] + key[-3]
    return ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), point)


def aes_cbc(key, data, encrypt):
    cipher = Cipher(algorithms.AES(key), modes.CBC(bytes(16)))
    op = cipher.encryptor() if encrypt else cipher.decryptor()
    return op.update(data) + op.finalize()


class Authenticator:
    """The CTAP2 part: takes a CBOR request, returns status and response."""

    def __init__(self):
        self.credentials = {}  # credential ID -> (private key, CredRandom)
        self.key_agreement = ec.generate_private_key(ec.SECP256R1())
        self.counter = 0

    def handle(self, request):
        command, params = request[0], cbor.decode(request[1:]) if len(request) > 1 else {}
        handler = {GET_INFO: self.get_info, MAKE_CREDENTIAL: self.make_credential,
                   GET_ASSERTION: self.get_assertion, CLIENT_PIN: self.client_pin}.get(command)
        if handler is None:
            return bytes([ERR_INVALID_COMMAND])
        status, response = handler(params)
        return bytes([status]) + (cbor.encode(response) if response is not None else b"")

    def get_info(self, params):
        return OK, {1: ["FIDO_2_0"], 2: ["hmac-secret"], 3: AAGUID,
                    4: {"rk": False, "up": True, "plat": False, "clientPin": False},
                    5: 1200, 6: [1]}

    def auth_data(self, rp_id, flags, extensions=None, attested=b""):
        self.counter += 1
        data = hashlib.sha256(rp_id.encode()).digest() + bytes([flags])
        data += struct.pack(">I", self.counter) + attested
        if extensions is not None:
            data += cbor.encode(extensions)
        return data

    def make_credential(self, params):
        client_data_hash, rp, algs = params.get(1), params.get(2), params.get(4, [])
        if client_data_hash is None or rp is None:
            return ERR_INVALID_PARAMETER, None
        if not any(a.get("alg") == COSE_ES256 for a in algs):
            return ERR_UNSUPPORTED_ALGORITHM, None
        if params.get(7, {}).get("rk") or params.get(7, {}).get("uv"):
            return ERR_INVALID_OPTION, None
        key = ec.generate_private_key(ec.SECP256R1())
        cred_id = os.urandom(32)
        self.credentials[cred_id] = (key, os.urandom(32))
        attested = AAGUID + struct.pack(">H", len(cred_id)) + cred_id
        attested += cbor.encode(cose_public_key(key.public_key(), COSE_ES256))
        flags = FLAG_UP | FLAG_AT
        extensions = None
        if params.get(6, {}).get("hmac-secret"):
            extensions = {"hmac-secret": True}
            flags |= FLAG_ED
        return OK, {1: "none", 2: self.auth_data(rp["id"], flags, extensions, attested), 3: {}}

    def shared_secret(self, platform_key):
        peer = public_key_from_cose(platform_key)
        z = self.key_agreement.exchange(ec.ECDH(), peer)
        return hashlib.sha256(z).digest()  # PIN/UV auth protocol 1

    def get_assertion(self, params):
        rp_id, client_data_hash = params.get(1), params.get(2)
        if rp_id is None or client_data_hash is None:
            return ERR_INVALID_PARAMETER, None
        if params.get(5, {}).get("uv"):
            return ERR_INVALID_OPTION, None
        for desc in params.get(3, []):
            if desc["id"] in self.credentials:
                cred_id = desc["id"]
                break
        else:
            return ERR_NO_CREDENTIALS, None
        key, cred_random = self.credentials[cred_id]

        flags = FLAG_UP if params.get(5, {}).get("up", True) else 0
        extensions = None
        secret_req = params.get(4, {}).get("hmac-secret")
        if secret_req is not None:
            secret = self.shared_secret(secret_req[1])
            salt_enc, salt_auth = secret_req[2], secret_req[3]
            if not hmac.compare_digest(
                    hmac.new(secret, salt_enc, hashlib.sha256).digest()[:16], salt_auth):
                return ERR_PIN_AUTH_INVALID, None
            salts = aes_cbc(secret, salt_enc, encrypt=False)
            output = b"".join(hmac.new(cred_random, salts[i:i + 32], hashlib.sha256).digest()
                              for i in range(0, len(salts), 32))
            extensions = {"hmac-secret": aes_cbc(secret, output, encrypt=True)}
            flags |= FLAG_ED

        auth_data = self.auth_data(rp_id, flags, extensions)
        signature = key.sign(auth_data + client_data_hash, ec.ECDSA(hashes.SHA256()))
        return OK, {1: {"id": cred_id, "type": "public-key"}, 2: auth_data, 3: signature}

    def client_pin(self, params):
        if params.get(2) == 0x02:  # getKeyAgreement
            key = cose_public_key(self.key_agreement.public_key(), COSE_ECDH_ES_HKDF_256)
            return OK, {1: key}
        if params.get(2) == 0x01:  # getRetries; no PIN is set
            return OK, {3: 8}
        return ERR_INVALID_PARAMETER, None


class CtapHid:
    """The CTAPHID transport: reassembles requests from 64-byte packets."""

    def __init__(self, authenticator, send_packet):
        self.authenticator = authenticator
        self.send_packet = send_packet
        self.next_cid = 1
        self.pending = None  # (cid, cmd, total length, data so far)

    def receive(self, packet):
        cid = struct.unpack(">I", packet[:4])[0]
        if packet[4] & 0x80:
            cmd, length = packet[4] & 0x7F, struct.unpack(">H", packet[5:7])[0]
            self.pending = (cid, cmd, length, packet[7:7 + length])
        elif self.pending and self.pending[0] == cid:
            c, cmd, length, data = self.pending
            self.pending = (c, cmd, length, data + packet[5:5 + length - len(data)])
        else:
            return
        cid, cmd, length, data = self.pending
        if len(data) >= length:
            self.pending = None
            self.dispatch(cid, cmd, data)

    def dispatch(self, cid, cmd, data):
        if cmd == CMD_INIT:
            new_cid = self.next_cid
            self.next_cid += 1
            caps = CAPABILITY_WINK | CAPABILITY_CBOR | CAPABILITY_NMSG
            self.send(cid, CMD_INIT, data[:8] + struct.pack(">IBBBBB", new_cid, 2, 1, 0, 0, caps))
        elif cmd == CMD_PING:
            self.send(cid, CMD_PING, data)
        elif cmd == CMD_WINK:
            self.send(cid, CMD_WINK, b"")
        elif cmd == CMD_CBOR:
            self.send(cid, CMD_CBOR, self.authenticator.handle(data))
        elif cmd == CMD_CANCEL:
            pass
        else:
            self.send(cid, CMD_ERROR, bytes([ERR_INVALID_CMD]))

    def send(self, cid, cmd, data):
        header = struct.pack(">IBH", cid, 0x80 | cmd, len(data))
        self.send_packet((header + data[:57]).ljust(PACKET, b"\0"))
        data, seq = data[57:], 0
        while data:
            self.send_packet((struct.pack(">IB", cid, seq) + data[:59]).ljust(PACKET, b"\0"))
            data, seq = data[59:], seq + 1


def run_uhid(hidraw_file):
    fd = os.open("/dev/uhid", os.O_RDWR)

    def send_packet(packet):
        event = struct.pack("<IH", UHID_INPUT2, len(packet)) + packet
        os.write(fd, event.ljust(UHID_EVENT_SIZE, b"\0"))

    before = set(glob.glob("/sys/class/hidraw/hidraw*"))
    create = struct.pack("<I128s64s64sHHIIII", UHID_CREATE2, b"Swissman virtual FIDO2 (TEST)",
                         b"", b"", len(REPORT_DESCRIPTOR), 0x03, 0x1209, 0x5357, 1, 0)
    os.write(fd, (create + REPORT_DESCRIPTOR).ljust(UHID_EVENT_SIZE, b"\0"))

    hid = CtapHid(Authenticator(), send_packet)
    announced = False
    while True:
        # The hidraw node shows up shortly after the device starts.
        if not announced:
            new = set(glob.glob("/sys/class/hidraw/hidraw*")) - before
            if new:
                path = "/dev/" + os.path.basename(new.pop())
                if hidraw_file:
                    with open(hidraw_file + ".tmp", "w") as f:
                        f.write(path + "\n")
                    os.rename(hidraw_file + ".tmp", hidraw_file)
                else:
                    print(path, flush=True)
                announced = True
        if not select.select([fd], [], [], 0.2)[0]:
            continue
        event = os.read(fd, UHID_EVENT_SIZE)
        if struct.unpack("<I", event[:4])[0] == UHID_OUTPUT:
            data, size = event[4:4 + 4096], struct.unpack("<H", event[4 + 4096:4 + 4098])[0]
            report = data[:size]
            if size == PACKET + 1:  # leading report number 0
                report = report[1:]
            hid.receive(report)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--hidraw-file")
    run_uhid(parser.parse_args().hidraw_file)


if __name__ == "__main__":
    main()
