package com.luxebank.auth

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import com.luxebank.TestcontainersConfiguration
import com.luxebank.common.security.SecretHasher
import com.luxebank.users.User
import com.luxebank.users.UserRepository
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.http.MediaType
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.ResultActionsDsl
import org.springframework.test.web.servlet.delete
import org.springframework.test.web.servlet.get
import org.springframework.test.web.servlet.post
import org.springframework.test.web.servlet.put
import java.util.UUID

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Import(TestcontainersConfiguration::class)
class AuthFlowIntegrationTest(
    @Autowired private val mockMvc: MockMvc,
    @Autowired private val objectMapper: ObjectMapper,
    @Autowired private val users: UserRepository,
    @Autowired private val hasher: SecretHasher,
    @Autowired private val jdbc: JdbcTemplate,
) {
    private lateinit var citizenId: String
    private val password = "Str0ng#Pass"
    private val pin = "482193"

    @BeforeEach
    fun createCustomer() {
        citizenId = randomCitizenId()
        users.save(
            User(
                citizenIdHash = hasher.identityHash(citizenId),
                passwordHash = hasher.hashSecret(password),
                phone = "0812344521",
                firstNameTh = "นกน้อย",
                firstNameEn = "Noknoi",
                tier = "GOLD",
            ),
        )
    }

    @Test
    fun `full registration then PIN login, refresh and logout`() {
        val key = TestDeviceKey()
        val session = registerDevice(key)
        val deviceId = UUID.fromString(session["deviceId"].asText())

        mockMvc
            .get("/api/v1/me") {
                bearer(session["accessToken"].asText())
                header("Accept-Language", "en")
            }.andExpect {
                status { isOk() }
                jsonPath("$.firstName") { value("Noknoi") }
                jsonPath("$.maskedPhone") { value("08X-XXX-4521") }
            }

        val login = loginWithPin(key, deviceId, pin).andExpect { status { isOk() } }.json()
        val refreshed =
            post("/api/v1/auth/refresh", mapOf("refreshToken" to login["refreshToken"].asText()))
                .andExpect { status { isOk() } }
                .json()
        assertThat(refreshed["refreshToken"].asText()).isNotEqualTo(login["refreshToken"].asText())

        mockMvc.post("/api/v1/auth/logout") { bearer(refreshed["accessToken"].asText()) }.andExpect { status { isNoContent() } }
        post("/api/v1/auth/refresh", mapOf("refreshToken" to refreshed["refreshToken"].asText()))
            .andExpect { status { isUnauthorized() } }
        post("/api/v1/auth/challenge", mapOf("deviceId" to deviceId)).andExpect {
            status { isNotFound() }
            jsonPath("$.error.code") { value("DEVICE_NOT_FOUND") }
        }
    }

    @Test
    fun `wrong password reports remaining attempts and locks the account`() {
        repeat(4) { attempt ->
            post("/api/v1/auth/register", mapOf("citizenId" to citizenId, "password" to "wrong"))
                .andExpect {
                    status { isUnauthorized() }
                    jsonPath("$.error.code") { value("INVALID_CREDENTIALS") }
                    jsonPath("$.error.remainingAttempts") { value(4 - attempt) }
                }
        }
        post("/api/v1/auth/register", mapOf("citizenId" to citizenId, "password" to "wrong"))
            .andExpect { jsonPath("$.error.code") { value("ACCOUNT_LOCKED") } }
        post("/api/v1/auth/register", mapOf("citizenId" to citizenId, "password" to password))
            .andExpect { jsonPath("$.error.code") { value("ACCOUNT_LOCKED") } }
    }

    @Test
    fun `unknown customer gets the same answer as a wrong password`() {
        post("/api/v1/auth/register", mapOf("citizenId" to randomCitizenId(), "password" to password)).andExpect {
            status { isUnauthorized() }
            jsonPath("$.error.code") { value("INVALID_CREDENTIALS") }
        }
    }

    @Test
    fun `otp locks after five wrong codes`() {
        val ref = startRegistration()
        repeat(4) {
            post("/api/v1/auth/otp/verify", mapOf("otpRef" to ref, "code" to "111111"))
                .andExpect { jsonPath("$.error.code") { value("OTP_INVALID") } }
        }
        post("/api/v1/auth/otp/verify", mapOf("otpRef" to ref, "code" to "111111"))
            .andExpect { jsonPath("$.error.code") { value("OTP_LOCKED") } }
        post("/api/v1/auth/otp/verify", mapOf("otpRef" to ref, "code" to "000000"))
            .andExpect { jsonPath("$.error.code") { value("OTP_EXPIRED") } }
    }

    @Test
    fun `registration token works once and weak pins are refused`() {
        val token = registrationToken()
        val key = TestDeviceKey()
        post("/api/v1/auth/devices", deviceBody(token, key, "123456"))
            .andExpect { jsonPath("$.error.code") { value("PIN_POLICY_VIOLATION") } }
        post("/api/v1/auth/devices", deviceBody(token, key, pin)).andExpect { status { isOk() } }
        post("/api/v1/auth/devices", deviceBody(token, key, pin))
            .andExpect { jsonPath("$.error.code") { value("REGISTRATION_EXPIRED") } }
    }

    @Test
    fun `invalid device key is refused`() {
        post(
            "/api/v1/auth/devices",
            deviceBody(
                registrationToken(),
                keyBase64 = "BAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                pin = pin,
            ),
        )
            .andExpect { jsonPath("$.error.code") { value("INVALID_DEVICE_KEY") } }
    }

    @Test
    fun `registering a new device revokes the old one`() {
        val oldKey = TestDeviceKey()
        val oldSession = registerDevice(oldKey)
        registerDevice(TestDeviceKey())

        post("/api/v1/auth/challenge", mapOf("deviceId" to oldSession["deviceId"].asText()))
            .andExpect { jsonPath("$.error.code") { value("DEVICE_NOT_FOUND") } }
        post("/api/v1/auth/refresh", mapOf("refreshToken" to oldSession["refreshToken"].asText()))
            .andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `login needs a signature from the bound device key`() {
        val key = TestDeviceKey()
        val deviceId = UUID.fromString(registerDevice(key)["deviceId"].asText())
        loginWithPin(TestDeviceKey(), deviceId, pin).andExpect { jsonPath("$.error.code") { value("SIGNATURE_INVALID") } }
    }

    @Test
    fun `challenge cannot be replayed`() {
        val key = TestDeviceKey()
        val deviceId = UUID.fromString(registerDevice(key)["deviceId"].asText())
        val challenge = challenge(deviceId)
        val body =
            mapOf(
                "deviceId" to deviceId,
                "challenge" to challenge,
                "signature" to key.signBase64(challenge),
                "method" to "PIN",
                "pin" to pin,
            )
        post("/api/v1/auth/login", body).andExpect { status { isOk() } }
        post("/api/v1/auth/login", body).andExpect { jsonPath("$.error.code") { value("CHALLENGE_INVALID") } }
    }

    @Test
    fun `five wrong pins lock the device and revoke its sessions`() {
        val key = TestDeviceKey()
        val session = registerDevice(key)
        val deviceId = UUID.fromString(session["deviceId"].asText())
        repeat(4) { attempt ->
            loginWithPin(key, deviceId, "908172").andExpect {
                jsonPath("$.error.code") { value("PIN_INVALID") }
                jsonPath("$.error.remainingAttempts") { value(4 - attempt) }
            }
        }
        loginWithPin(key, deviceId, "908172").andExpect { jsonPath("$.error.code") { value("PIN_LOCKED") } }
        loginWithPin(key, deviceId, pin).andExpect { jsonPath("$.error.code") { value("PIN_LOCKED") } }
        post("/api/v1/auth/refresh", mapOf("refreshToken" to session["refreshToken"].asText())).andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `reusing a refresh token revokes the whole family`() {
        val session = registerDevice(TestDeviceKey())
        val first = session["refreshToken"].asText()
        val second = post("/api/v1/auth/refresh", mapOf("refreshToken" to first)).json()["refreshToken"].asText()

        post("/api/v1/auth/refresh", mapOf("refreshToken" to first)).andExpect { status { isUnauthorized() } }
        post("/api/v1/auth/refresh", mapOf("refreshToken" to second)).andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `face id login uses the separate biometric key`() {
        val deviceKey = TestDeviceKey()
        val biometricKey = TestDeviceKey()
        val session = registerDevice(deviceKey)
        val deviceId = UUID.fromString(session["deviceId"].asText())

        loginWithBiometric(biometricKey, deviceId).andExpect { jsonPath("$.error.code") { value("BIOMETRIC_NOT_ENABLED") } }
        mockMvc
            .put("/api/v1/auth/biometric") {
                bearer(session["accessToken"].asText())
                jsonBody(mapOf("biometricPublicKey" to biometricKey.base64))
            }.andExpect { status { isNoContent() } }

        loginWithBiometric(deviceKey, deviceId).andExpect { jsonPath("$.error.code") { value("SIGNATURE_INVALID") } }
        loginWithBiometric(biometricKey, deviceId).andExpect { status { isOk() } }

        mockMvc.delete("/api/v1/auth/biometric") { bearer(session["accessToken"].asText()) }.andExpect { status { isNoContent() } }
        loginWithBiometric(biometricKey, deviceId).andExpect { jsonPath("$.error.code") { value("BIOMETRIC_NOT_ENABLED") } }
    }

    @Test
    fun `pin can be changed with the current pin`() {
        val key = TestDeviceKey()
        val session = registerDevice(key)
        val deviceId = UUID.fromString(session["deviceId"].asText())
        mockMvc
            .put("/api/v1/auth/pin") {
                bearer(session["accessToken"].asText())
                jsonBody(mapOf("currentPin" to pin, "newPin" to "135790"))
            }.andExpect { status { isNoContent() } }
        loginWithPin(key, deviceId, pin).andExpect { jsonPath("$.error.code") { value("PIN_INVALID") } }
        loginWithPin(key, deviceId, "135790").andExpect { status { isOk() } }
    }

    @Test
    fun `protected endpoints reject missing and forged tokens`() {
        mockMvc.get("/api/v1/me").andExpect { status { isUnauthorized() } }
        mockMvc.get("/api/v1/me") { bearer("eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.") }.andExpect { status { isUnauthorized() } }
    }

    @Test
    fun `audit trail is hash-chained and never stores secrets`() {
        val startId = jdbc.queryForObject("SELECT coalesce(max(id), 0) FROM audit_log", Long::class.java)!!
        registerDevice(TestDeviceKey())
        val rows =
            jdbc.queryForList(
                "SELECT id, previous_hash, row_hash, metadata::text AS metadata FROM audit_log WHERE id > ? ORDER BY id",
                startId,
            )

        assertThat(rows.map { it["metadata"].toString() }).noneMatch { it.contains(pin) || it.contains(password) || it.contains(citizenId) }
        rows.zipWithNext().forEach { (previous, current) -> assertThat(current["previous_hash"]).isEqualTo(previous["row_hash"]) }
        assertThat(rows.size).isGreaterThanOrEqualTo(3)
    }

    // --- helpers -------------------------------------------------------------

    private fun startRegistration(): String =
        post("/api/v1/auth/register", mapOf("citizenId" to citizenId, "password" to password))
            .andExpect {
                status { isOk() }
                jsonPath("$.maskedPhone") { value("08X-XXX-4521") }
            }.json()["otpRef"]
            .asText()

    private fun registrationToken(): String =
        post("/api/v1/auth/otp/verify", mapOf("otpRef" to startRegistration(), "code" to "000000"))
            .andExpect { status { isOk() } }
            .json()["registrationToken"]
            .asText()

    private fun registerDevice(key: TestDeviceKey): JsonNode =
        post("/api/v1/auth/devices", deviceBody(registrationToken(), key, pin)).andExpect { status { isOk() } }.json()

    private fun deviceBody(
        token: String,
        key: TestDeviceKey? = null,
        pin: String,
        keyBase64: String? = null,
    ) = mapOf(
        "registrationToken" to token,
        "pin" to pin,
        "deviceName" to "iPhone",
        "devicePublicKey" to (keyBase64 ?: key!!.base64),
    )

    private fun deviceBody(
        token: String,
        key: TestDeviceKey,
        pin: String,
    ) = deviceBody(token, key, pin, null)

    private fun challenge(deviceId: UUID): String =
        post(
            "/api/v1/auth/challenge",
            mapOf("deviceId" to deviceId),
        ).json()["challenge"].asText()

    private fun loginWithPin(
        key: TestDeviceKey,
        deviceId: UUID,
        pin: String,
    ): ResultActionsDsl {
        val challenge = challenge(deviceId)
        return post(
            "/api/v1/auth/login",
            mapOf(
                "deviceId" to deviceId,
                "challenge" to challenge,
                "signature" to key.signBase64(challenge),
                "method" to "PIN",
                "pin" to pin,
            ),
        )
    }

    private fun loginWithBiometric(
        key: TestDeviceKey,
        deviceId: UUID,
    ): ResultActionsDsl {
        val challenge = challenge(deviceId)
        return post(
            "/api/v1/auth/login",
            mapOf("deviceId" to deviceId, "challenge" to challenge, "signature" to key.signBase64(challenge), "method" to "BIOMETRIC"),
        )
    }

    private fun post(
        url: String,
        body: Any,
    ) = mockMvc.post(url) { jsonBody(body) }

    private fun org.springframework.test.web.servlet.MockHttpServletRequestDsl.jsonBody(body: Any) {
        contentType = MediaType.APPLICATION_JSON
        content = objectMapper.writeValueAsString(body)
    }

    private fun org.springframework.test.web.servlet.MockHttpServletRequestDsl.bearer(token: String) {
        header("Authorization", "Bearer $token")
    }

    private fun ResultActionsDsl.json(): JsonNode = objectMapper.readTree(andReturn().response.contentAsString)

    private fun randomCitizenId(): String {
        val digits = (1..12).map { if (it == 1) (1..8).random() else (0..9).random() }
        val sum = digits.withIndex().sumOf { (i, d) -> d * (13 - i) }
        return digits.joinToString("") + ((11 - sum % 11) % 10)
    }
}
