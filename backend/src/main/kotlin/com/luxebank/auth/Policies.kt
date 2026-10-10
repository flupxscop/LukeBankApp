package com.luxebank.auth

/** Thai national ID: 13 digits, last digit is a mod-11 checksum. */
object CitizenId {
    private const val LENGTH = 13
    private const val WEIGHT_BASE = 13
    private const val MOD = 11
    private const val DIGITS = 10

    fun normalize(raw: String): String? {
        val digits = raw.filter { it.isDigit() }
        if (digits.length != LENGTH || raw.any { !it.isDigit() && it != '-' && it != ' ' }) return null
        val values = digits.map { it.digitToInt() }
        val sum = (0 until LENGTH - 1).sumOf { values[it] * (WEIGHT_BASE - it) }
        val check = (MOD - sum % MOD) % DIGITS
        return if (check == values.last()) digits else null
    }
}

/** AUTH-02: six digits, not all the same, not a straight run up or down. */
object PinPolicy {
    private const val LENGTH = 6

    fun isAcceptable(pin: String): Boolean {
        if (pin.length != LENGTH || !pin.all { it.isDigit() }) return false
        val digits = pin.map { it.digitToInt() }
        if (digits.toSet().size == 1) return false
        val steps = digits.zipWithNext { a, b -> b - a }.toSet()
        return steps != setOf(1) && steps != setOf(-1)
    }
}
