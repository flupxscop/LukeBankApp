package com.luxebank.payments

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestHeader
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

/** Thai banks reachable through ITMX. LuxeBank's own code is used for internal transfers. */
enum class Bank(
    val code: String,
    val nameTh: String,
    val nameEn: String,
    val monogram: String,
) {
    LUXE("LUXE", "ลักซ์แบงก์", "LuxeBank", "LX"),
    KBANK("KBANK", "กสิกรไทย", "Kasikornbank", "K"),
    SCB("SCB", "ไทยพาณิชย์", "Siam Commercial Bank", "SCB"),
    BBL("BBL", "กรุงเทพ", "Bangkok Bank", "BBL"),
    KTB("KTB", "กรุงไทย", "Krungthai Bank", "KTB"),
    BAY("BAY", "กรุงศรีอยุธยา", "Krungsri", "BAY"),
    TTB("TTB", "ทีทีบี", "TMBThanachart", "TTB"),
    GSB("GSB", "ออมสิน", "Government Savings Bank", "GSB"),
    ;

    fun name(english: Boolean) = if (english) nameEn else nameTh

    companion object {
        fun of(code: String?): Bank? = entries.firstOrNull { it.code == code }

        /** Banks a customer can pick for an other-bank transfer. */
        val external: List<Bank> get() = entries.filter { it != LUXE }
    }
}

/** What recipients and slips show instead of full names and numbers (13.3.1). */
object Masking {
    private val titles = setOf("นาย", "นาง", "นางสาว", "บริษัท", "Mr.", "Mrs.", "Ms.", "Miss")
    private const val VISIBLE_LETTERS = 2
    private const val VISIBLE_DIGITS = 4

    /** "นาย สมชาย ใจดี" → "นาย สมชาย ใจ**"; the title and first name stay readable. */
    fun name(full: String): String {
        val words = full.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        val keep = if (words.firstOrNull() in titles) 2 else 1
        return words.mapIndexed { index, word -> if (index < keep) word else word.take(VISIBLE_LETTERS) + "**" }.joinToString(" ")
    }

    /** "1234567890" → "x7890". */
    fun account(number: String): String = "x" + number.filter(Char::isDigit).takeLast(VISIBLE_DIGITS)
}

data class BankResponse(
    val code: String,
    val name: String,
    val monogram: String,
)

@RestController
@RequestMapping("/api/v1/banks")
class BanksController {
    @GetMapping
    fun banks(
        @RequestHeader("Accept-Language", required = false) language: String?,
    ): List<BankResponse> = Bank.external.map { BankResponse(it.code, it.name(language.isEnglish()), it.monogram) }
}

fun String?.isEnglish() = this?.startsWith("en") == true
