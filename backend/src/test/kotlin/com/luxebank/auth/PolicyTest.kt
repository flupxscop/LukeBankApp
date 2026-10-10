package com.luxebank.auth

import com.luxebank.devices.DeviceKeys
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

class PolicyTest {
    @Test
    fun `accepts a valid citizen id with separators`() {
        assertThat(CitizenId.normalize("1-2345-67890-12-1")).isEqualTo("1234567890121")
    }

    @ParameterizedTest
    @ValueSource(strings = ["1-2345-67890-12-4", "123456789012", "12345678901211", "1234567890a21", "1234567890121; DROP"])
    fun `rejects citizen ids with a wrong checksum or shape`(value: String) {
        assertThat(CitizenId.normalize(value)).isNull()
    }

    @ParameterizedTest
    @ValueSource(strings = ["123456", "654321", "111111", "000000", "12345", "1234567", "12a456"])
    fun `rejects weak or malformed pins`(pin: String) {
        assertThat(PinPolicy.isAcceptable(pin)).isFalse()
    }

    @ParameterizedTest
    @ValueSource(strings = ["482193", "135790", "112233", "908172"])
    fun `accepts reasonable pins`(pin: String) {
        assertThat(PinPolicy.isAcceptable(pin)).isTrue()
    }

    @Test
    fun `device keys must be points on P-256`() {
        val key = TestDeviceKey()
        assertThat(DeviceKeys.isValid(key.x963)).isTrue()
        assertThat(DeviceKeys.isValid(ByteArray(65) { 4 })).isFalse()
        assertThat(DeviceKeys.isValid(key.x963.copyOf(33))).isFalse()
    }

    @Test
    fun `verifies signatures only from the matching key`() {
        val key = TestDeviceKey()
        val other = TestDeviceKey()
        val message = "challenge".toByteArray()
        assertThat(DeviceKeys.verify(key.x963, message, key.sign(message))).isTrue()
        assertThat(DeviceKeys.verify(key.x963, message, other.sign(message))).isFalse()
        assertThat(DeviceKeys.verify(key.x963, "other".toByteArray(), key.sign(message))).isFalse()
    }
}
