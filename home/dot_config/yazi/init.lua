require("git"):setup()

require("full-border"):setup({
	-- Available values: ui.Border.PLAIN, ui.Border.ROUNDED
	type = ui.Border.ROUNDED,
})

-- DuckDB plugin configuration
require("duckdb"):setup()

require("smart-enter"):setup({
	open_multi = true,
})
