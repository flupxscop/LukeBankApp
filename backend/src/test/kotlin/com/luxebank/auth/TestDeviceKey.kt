package com.luxebank.auth

import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.util.Base64

/** Stands in for a Secure Enclave key in tests: P-256, X9.63 export, DER ECDSA signatures. */
class TestDeviceKey {
    private val pair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()

    val x963: ByteArray =
        (pair.public as ECPublicKey).w.let { point ->
            byteArrayOf(0x04) + point.affineX.toFixed() + point.affineY.toFixed()
        }

    val base64: String get() = Base64.getEncoder().encodeToString(x963)

    fun sign(message: ByteArray): ByteArray =
        Signature.getInstance("SHA256withECDSA").run {
            initSign(pair.private)
            update(message)
            sign()
        }

    fun signBase64(challenge: String): String = Base64.getEncoder().encodeToString(sign(challenge.toByteArray()))

    private fun BigInteger.toFixed(): ByteArray {
        val raw = toByteArray().dropWhile { it == 0.toByte() }.toByteArray()
        return ByteArray(32 - raw.size) + raw
    }
}
