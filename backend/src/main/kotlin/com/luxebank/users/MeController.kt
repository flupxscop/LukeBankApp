package com.luxebank.users

import com.luxebank.auth.CurrentDevice
import com.luxebank.common.error.ApiException
import com.luxebank.common.error.ErrorCode
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

data class MeResponse(
    val firstName: String,
    val tier: String,
    val maskedPhone: String,
)

@RestController
@RequestMapping("/api/v1/me")
class MeController(
    private val users: UserRepository,
) {
    @GetMapping
    fun me(
        current: CurrentDevice,
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): MeResponse {
        val user = users.findById(current.userId).orElseThrow { ApiException(ErrorCode.NOT_FOUND, "Resource not found") }
        val firstName = if (language?.startsWith("en") == true) user.firstNameEn else user.firstNameTh
        return MeResponse(firstName, user.tier, user.maskedPhone)
    }
}
