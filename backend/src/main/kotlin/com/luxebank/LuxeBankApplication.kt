package com.luxebank

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class LuxeBankApplication

fun main(args: Array<String>) {
    runApplication<LuxeBankApplication>(*args)
}
