package com.luxebank.auth

import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import com.luxebank.payments.PaymentAuthorizer
import com.luxebank.payments.PaymentProof
import jakarta.validation.constraints.Size
import org.springframework.stereotype.Component
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

/** Proof that the signed-in customer is holding the bound device right now, for sensitive actions (13.1 A07/A08). */
data class StepUpProof(
    @field:Size(max = 128) val challenge: String,
    val method: LoginMethod,
    @field:Size(max = 200) val signature: String,
    @field:Size(max = 6) val pin: String? = null,
)

/**
 * Verifies a [StepUpProof]: the challenge was issued to this device and not used yet, and the device key
 * (with the PIN) or the Face ID key signed it. Shares lockout rules with payment confirmation.
 */
@Component
class StepUpVerifier(
    private val challenges: ChallengeService,
    private val authorizer: PaymentAuthorizer,
) {
    fun verify(
        current: CurrentDevice,
        proof: StepUpProof,
        requireBiometric: Boolean,
    ) {
        if (!challenges.consume(current.deviceId, proof.challenge)) {
            throw ApiException(ErrorCode.CHALLENGE_INVALID, "Challenge expired, try again")
        }
        authorizer.authorize(current, proof.challenge, PaymentProof(proof.method, proof.signature, proof.pin), requireBiometric)
    }
}

@RestController
@RequestMapping("/api/v1/challenges")
class ChallengesController(
    private val challenges: ChallengeService,
) {
    /** A single-use challenge for the signed-in device, signed in a [StepUpProof]. */
    @PostMapping
    fun issue(current: CurrentDevice): ChallengeResponse = ChallengeResponse(challenges.issue(current.deviceId), challenges.ttlSeconds)
}
