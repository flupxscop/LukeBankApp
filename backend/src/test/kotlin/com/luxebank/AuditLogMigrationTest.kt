package com.luxebank

import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.context.annotation.Import
import org.springframework.jdbc.core.JdbcTemplate

@SpringBootTest
@Import(TestcontainersConfiguration::class)
class AuditLogMigrationTest(
    @Autowired private val jdbc: JdbcTemplate,
) {
    @Test
    fun `audit log accepts inserts but rejects updates and deletes`() {
        jdbc.update("INSERT INTO audit_log (action, row_hash) VALUES ('TEST_EVENT', repeat('a', 64))")
        assertThat(jdbc.queryForObject("SELECT count(*) FROM audit_log WHERE action = 'TEST_EVENT'", Long::class.java)).isEqualTo(1)

        assertThatThrownBy { jdbc.update("UPDATE audit_log SET action = 'CHANGED'") }.hasMessageContaining("append-only")
        assertThatThrownBy { jdbc.update("DELETE FROM audit_log") }.hasMessageContaining("append-only")
    }
}
