


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Match sys_pll C1/C2. Parentheses are essential when these expressions
// expand inside the refresh counter's arithmetic and comparisons.
`define   SDR_CLK_HZ                       50000000
`define   SDR_CLK_PERIOD                   (1000000000 / `SDR_CLK_HZ)
// init_cnt visits both zero and this terminal value. Subtract one so the
// EM638325 requires 4096 refresh commands per 64 ms (not 2048, despite
// ROW_WIDTH=11). Include the wrap clock in the retention budget.
`define   SELF_REFRESH_INTERVAL            ((64000000 / `SDR_CLK_PERIOD / 4096) - 1)

