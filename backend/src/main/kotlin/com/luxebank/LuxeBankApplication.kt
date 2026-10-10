package com.luxebank

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.context.properties.ConfigurationPropertiesScan
import org.springframework.boot.runApplication

@SpringBootApplication
@ConfigurationPropertiesScan
class LuxeBankApplication

fun main(args: Array<String>) {
    runApplication<LuxeBankApplication>(*args)
}
