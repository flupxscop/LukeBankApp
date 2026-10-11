package com.luxebank.users

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.Table
import jakarta.persistence.Version
import org.springframework.data.jpa.repository.JpaRepository
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "users")
class User(
    @Id
    val id: UUID = UUID.randomUUID(),
    @Column(name = "citizen_id_hash", nullable = false, unique = true)
    val citizenIdHash: String,
    @Column(name = "password_hash", nullable = false)
    var passwordHash: String,
    @Column(nullable = false)
    val phone: String,
    @Column(name = "first_name_th", nullable = false)
    val firstNameTh: String,
    @Column(name = "first_name_en", nullable = false)
    val firstNameEn: String,
    @Column(name = "last_name_th", nullable = false)
    val lastNameTh: String = "",
    @Column(name = "last_name_en", nullable = false)
    val lastNameEn: String = "",
    @Column(nullable = false)
    val tier: String,
    @Column(name = "failed_password_attempts", nullable = false)
    var failedPasswordAttempts: Int = 0,
    @Column(name = "locked_until")
    var lockedUntil: Instant? = null,
    @Column(name = "created_at", nullable = false)
    val createdAt: Instant = Instant.now(),
    @Version
    var version: Long = 0,
) {
    /** "08X-XXX-4521" — the only form of the phone number that leaves the server. */
    val maskedPhone: String
        get() = "08X-XXX-" + phone.takeLast(MASK_VISIBLE)

    private companion object {
        const val MASK_VISIBLE = 4
    }
}

interface UserRepository : JpaRepository<User, UUID> {
    fun findByCitizenIdHash(citizenIdHash: String): User?
}
