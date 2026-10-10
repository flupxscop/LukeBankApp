package com.luxebank.devices

import org.bouncycastle.jce.ECNamedCurveTable
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.jce.spec.ECPublicKeySpec
import java.security.KeyFactory
import java.security.PublicKey
import java.security.Signature

/**
 * P-256 keys created in the iPhone Secure Enclave, exported as X9.63 (0x04 || X || Y).
 * Signatures are DER ECDSA over SHA-256 (`ecdsaSignatureMessageX962SHA256`).
 */
object DeviceKeys {
    private const val UNCOMPRESSED_P256_LENGTH = 65
    private const val UNCOMPRESSED_PREFIX: Byte = 0x04
    private val provider = BouncyCastleProvider()
    private val curve = ECNamedCurveTable.getParameterSpec("secp256r1")

    /** Rejects anything that is not a valid point on P-256. */
    fun isValid(x963: ByteArray): Boolean = runCatching { publicKey(x963) }.isSuccess

    fun verify(
        x963: ByteArray,
        message: ByteArray,
        derSignature: ByteArray,
    ): Boolean =
        runCatching {
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(publicKey(x963))
                update(message)
                verify(derSignature)
            }
        }.getOrDefault(false)

    private fun publicKey(x963: ByteArray): PublicKey {
        require(x963.size == UNCOMPRESSED_P256_LENGTH && x963[0] == UNCOMPRESSED_PREFIX) { "Not an uncompressed P-256 key" }
        val point = curve.curve.decodePoint(x963)
        require(point.isValid) { "Point is not on the curve" }
        return KeyFactory.getInstance("EC", provider).generatePublic(ECPublicKeySpec(point, curve))
    }
}
