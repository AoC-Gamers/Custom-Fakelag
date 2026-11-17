#if defined _console_table_included
	#endinput
#endif
#define _console_table_included

/**
 * Reusable console panel/table renderer for monospaced SourceMod console output.
 *
 * This include intentionally focuses on fixed-width console panels:
 * - optional header lines
 * - optional body table
 * - optional footer lines
 * - typed cells (string/int/float)
 * - stable truncation and alignment
 *
 * The first consumer is expected to be player_fakelag balance output.
 */

#define CONSOLE_TABLE_MAX_WIDTH 96
#define CONSOLE_TABLE_MAX_HEADER_LINES 8
#define CONSOLE_TABLE_MAX_FOOTER_LINES 8
#define CONSOLE_TABLE_MAX_COLUMNS 8
#define CONSOLE_TABLE_MAX_ROWS 32
#define CONSOLE_TABLE_MAX_CELL_TEXT 128

/**
 * @brief Horizontal alignment used when rendering one table column.
 */
enum ConsoleTableAlignment
{
	ConsoleTableAlignment_Left = 0,
	ConsoleTableAlignment_Right,
	ConsoleTableAlignment_Center
}

/**
 * @brief Logical type of one rendered cell.
 */
enum ConsoleTableCellType
{
	ConsoleTableCellType_String = 0,
	ConsoleTableCellType_Int,
	ConsoleTableCellType_Float
}

/**
 * @brief Static schema for one column in the body table.
 */
enum struct ConsoleTableColumn
{
	char title[32];
	int width;
	ConsoleTableAlignment alignment;
	ConsoleTableCellType typeHint;
}

/**
 * @brief One typed value stored in a row before formatting.
 */
enum struct ConsoleTableCell
{
	ConsoleTableCellType type;
	char stringValue[CONSOLE_TABLE_MAX_CELL_TEXT];
	int intValue;
	float floatValue;
	int floatPrecision;
}

/**
 * @brief One row in the body table.
 */
enum struct ConsoleTableRow
{
	int cellCount;
	ConsoleTableCell cells[CONSOLE_TABLE_MAX_COLUMNS];
}

/**
 * @brief One stored text line used by the panel header or footer.
 */
enum struct ConsolePanelLine
{
	char text[CONSOLE_TABLE_MAX_CELL_TEXT];
	bool safeAsciiOnly;
}

/**
 * @brief Body table state: schema, rows, and current row-build state.
 */
enum struct ConsoleTable
{
	int columnCount;
	int rowCount;
	bool buildingRow;
	ConsoleTableColumn columns[CONSOLE_TABLE_MAX_COLUMNS];
	ConsoleTableRow rows[CONSOLE_TABLE_MAX_ROWS];
}

/**
 * @brief Full renderable console panel with header, body table, and footer.
 */
enum struct ConsolePanel
{
	int width;
	bool safeAsciiOnly;
	int headerLineCount;
	int footerLineCount;
	ConsolePanelLine headerLines[CONSOLE_TABLE_MAX_HEADER_LINES];
	ConsolePanelLine footerLines[CONSOLE_TABLE_MAX_FOOTER_LINES];
	ConsoleTable table;
}

/**
 * @brief Clears table schema, rows, and in-progress row state.
 *
 * @param table		Table instance to reset.
 */
stock void ConsoleTable_Reset(ConsoleTable table)
{
	table.columnCount = 0;
	table.rowCount = 0;
	table.buildingRow = false;
}

/**
 * @brief Restores one panel to default compact settings.
 *
 * @param panel		Panel instance to reset.
 */
stock void ConsolePanel_Reset(ConsolePanel panel)
{
	panel.width = 58;
	panel.safeAsciiOnly = true;
	panel.headerLineCount = 0;
	panel.footerLineCount = 0;
	ConsoleTable_Reset(panel.table);
}

/**
 * @brief Sets the visible width of the panel, clamped to safe limits.
 *
 * @param panel		Panel instance to configure.
 * @param width		Requested visible width in characters.
 */
stock void ConsolePanel_SetWidth(ConsolePanel panel, int width)
{
	if (width < 16)
	{
		width = 16;
	}
	else if (width > CONSOLE_TABLE_MAX_WIDTH)
	{
		width = CONSOLE_TABLE_MAX_WIDTH;
	}

	panel.width = width;
}

/**
 * @brief Chooses whether display text should be normalized to console-safe ASCII.
 *
 * @param panel		Panel instance to configure.
 * @param enabled		True to normalize display text to safe ASCII.
 */
stock void ConsolePanel_EnableSafeAscii(ConsolePanel panel, bool enabled)
{
	panel.safeAsciiOnly = enabled;
}

/**
 * @brief Appends one header line.
 *
 * @param panel		Panel instance to modify.
 * @param text		Header line to append.
 * @return			True if the line was appended, false if the header is full.
 */
stock bool ConsolePanel_AddHeaderLine(ConsolePanel panel, const char[] text)
{
	if (panel.headerLineCount >= CONSOLE_TABLE_MAX_HEADER_LINES)
	{
		return false;
	}

	strcopy(panel.headerLines[panel.headerLineCount].text, CONSOLE_TABLE_MAX_CELL_TEXT, text);
	panel.headerLines[panel.headerLineCount].safeAsciiOnly = panel.safeAsciiOnly;
	panel.headerLineCount++;
	return true;
}

/**
 * @brief Appends one footer line.
 *
 * @param panel		Panel instance to modify.
 * @param text		Footer line to append.
 * @return			True if the line was appended, false if the footer is full.
 */
stock bool ConsolePanel_AddFooterLine(ConsolePanel panel, const char[] text)
{
	if (panel.footerLineCount >= CONSOLE_TABLE_MAX_FOOTER_LINES)
	{
		return false;
	}

	strcopy(panel.footerLines[panel.footerLineCount].text, CONSOLE_TABLE_MAX_CELL_TEXT, text);
	panel.footerLines[panel.footerLineCount].safeAsciiOnly = panel.safeAsciiOnly;
	panel.footerLineCount++;
	return true;
}

/**
 * @brief Appends one footer line preserving UTF-8 trimming rules.
 *
 * @param panel		Panel instance to modify.
 * @param text		Footer line to append.
 * @return			True if the line was appended, false if the footer is full.
 */
stock bool ConsolePanel_AddFooterUtf8Line(ConsolePanel panel, const char[] text)
{
	if (panel.footerLineCount >= CONSOLE_TABLE_MAX_FOOTER_LINES)
	{
		return false;
	}

	strcopy(panel.footerLines[panel.footerLineCount].text, CONSOLE_TABLE_MAX_CELL_TEXT, text);
	panel.footerLines[panel.footerLineCount].safeAsciiOnly = false;
	panel.footerLineCount++;
	return true;
}

/**
 * @brief Adds one column definition to the table schema.
 *
 * @param table			Table instance to modify.
 * @param title			Visible column title.
 * @param width			Column width in characters.
 * @param alignment		Horizontal alignment used for this column.
 * @param typeHint		Logical data type expected in this column.
 * @return				True if the column was added, false if the table is full.
 */
stock bool ConsoleTable_AddColumn(ConsoleTable table, const char[] title, int width, ConsoleTableAlignment alignment, ConsoleTableCellType typeHint)
{
	if (table.columnCount >= CONSOLE_TABLE_MAX_COLUMNS)
	{
		return false;
	}

	int columnIndex = table.columnCount;
	strcopy(table.columns[columnIndex].title, sizeof(table.columns[columnIndex].title), title);
	table.columns[columnIndex].width = width;
	table.columns[columnIndex].alignment = alignment;
	table.columns[columnIndex].typeHint = typeHint;
	table.columnCount++;
	return true;
}

/**
 * @brief Starts a new row.
 *
 * Cells can be appended until ConsoleTable_EndRow() is called.
 *
 * @param table		Table instance to modify.
 * @return			True if the row was opened, false otherwise.
 */
stock bool ConsoleTable_BeginRow(ConsoleTable table)
{
	if (table.buildingRow || table.rowCount >= CONSOLE_TABLE_MAX_ROWS)
	{
		return false;
	}

	table.rows[table.rowCount].cellCount = 0;
	table.buildingRow = true;
	return true;
}

/**
 * @brief Commits the current row to the table.
 *
 * @param table		Table instance to modify.
 * @return			True if the row was committed, false otherwise.
 */
stock bool ConsoleTable_EndRow(ConsoleTable table)
{
	if (!table.buildingRow)
	{
		return false;
	}

	table.buildingRow = false;
	table.rowCount++;
	return true;
}

/**
 * @brief Appends one string cell to the current row.
 *
 * @param table		Table instance to modify.
 * @param value		String value to append.
 * @return			True if the cell was appended, false otherwise.
 */
stock bool ConsoleTable_AddStringCell(ConsoleTable table, const char[] value)
{
	if (!table.buildingRow)
	{
		return false;
	}

	int rowIndex = table.rowCount;
	int cellIndex = table.rows[rowIndex].cellCount;
	if (cellIndex >= CONSOLE_TABLE_MAX_COLUMNS)
	{
		return false;
	}

	table.rows[rowIndex].cells[cellIndex].type = ConsoleTableCellType_String;
	strcopy(table.rows[rowIndex].cells[cellIndex].stringValue, CONSOLE_TABLE_MAX_CELL_TEXT, value);
	table.rows[rowIndex].cells[cellIndex].intValue = 0;
	table.rows[rowIndex].cells[cellIndex].floatValue = 0.0;
	table.rows[rowIndex].cells[cellIndex].floatPrecision = 0;
	table.rows[rowIndex].cellCount++;
	return true;
}

/**
 * @brief Appends one integer cell to the current row.
 *
 * @param table		Table instance to modify.
 * @param value		Integer value to append.
 * @return			True if the cell was appended, false otherwise.
 */
stock bool ConsoleTable_AddIntCell(ConsoleTable table, int value)
{
	if (!table.buildingRow)
	{
		return false;
	}

	int rowIndex = table.rowCount;
	int cellIndex = table.rows[rowIndex].cellCount;
	if (cellIndex >= CONSOLE_TABLE_MAX_COLUMNS)
	{
		return false;
	}

	table.rows[rowIndex].cells[cellIndex].type = ConsoleTableCellType_Int;
	table.rows[rowIndex].cells[cellIndex].stringValue[0] = '\0';
	table.rows[rowIndex].cells[cellIndex].intValue = value;
	table.rows[rowIndex].cells[cellIndex].floatValue = 0.0;
	table.rows[rowIndex].cells[cellIndex].floatPrecision = 0;
	table.rows[rowIndex].cellCount++;
	return true;
}

/**
 * @brief Appends one float cell to the current row.
 *
 * @param table			Table instance to modify.
 * @param value			Float value to append.
 * @param precision		Decimal precision used when rendering the value.
 * @return				True if the cell was appended, false otherwise.
 */
stock bool ConsoleTable_AddFloatCell(ConsoleTable table, float value, int precision = 1)
{
	if (!table.buildingRow)
	{
		return false;
	}

	int rowIndex = table.rowCount;
	int cellIndex = table.rows[rowIndex].cellCount;
	if (cellIndex >= CONSOLE_TABLE_MAX_COLUMNS)
	{
		return false;
	}

	table.rows[rowIndex].cells[cellIndex].type = ConsoleTableCellType_Float;
	table.rows[rowIndex].cells[cellIndex].stringValue[0] = '\0';
	table.rows[rowIndex].cells[cellIndex].intValue = 0;
	table.rows[rowIndex].cells[cellIndex].floatValue = value;
	table.rows[rowIndex].cells[cellIndex].floatPrecision = precision;
	table.rows[rowIndex].cellCount++;
	return true;
}

/**
 * @brief Returns true when the table contains at least one committed row.
 *
 * @param table		Table instance to inspect.
 * @return			True if the table has rows, false otherwise.
 */
stock bool ConsoleTable_HasRows(ConsoleTable table)
{
	return table.rowCount > 0;
}

/**
 * @brief Low-level output helper.
 *
 * Client 0 writes to the server console.
 *
 * @param client		Client index to print to, or 0 for the server console.
 * @param message		Message to print.
 */
stock void ConsolePanel_PrintMessage(int client, const char[] message)
{
	if (client == 0)
	{
		PrintToServer("%s", message);
		return;
	}

	PrintToConsole(client, "%s", message);
}

/**
 * @brief Builds a console-safe ASCII string.
 *
 * Replaces unsupported characters and truncates if needed.
 *
 * @param source		Source string.
 * @param buffer		Destination buffer.
 * @param maxlen		Maximum size of the destination buffer.
 * @param maxWidth		Maximum visible width in characters.
 */
stock void ConsolePanel_BuildSafeText(const char[] source, char[] buffer, int maxlen, int maxWidth)
{
	int inputIndex = 0;
	int outputIndex = 0;
	int charCount = 0;
	bool truncated = false;

	while (source[inputIndex] != '\0' && outputIndex < maxlen - 1)
	{
		if (charCount >= maxWidth)
		{
			truncated = true;
			break;
		}

		int charBytes = GetCharBytes(source[inputIndex]);
		if (charBytes > 1)
		{
			buffer[outputIndex++] = '?';
			charCount++;
			inputIndex += charBytes;
			continue;
		}

		char ch = source[inputIndex];
		if (ch < ' ' || ch > '~')
		{
			buffer[outputIndex++] = '?';
		}
		else
		{
			buffer[outputIndex++] = ch;
		}
		inputIndex++;
		charCount++;
	}

	if (source[inputIndex] != '\0')
	{
		truncated = true;
	}

	buffer[outputIndex] = '\0';
	if (!truncated || maxWidth <= 3 || outputIndex < 3)
	{
		return;
	}

	buffer[maxWidth - 3] = '\0';
	StrCat(buffer, maxlen, "...");
}

/**
 * @brief Builds a UTF-8-preserving trimmed string.
 *
 * Truncates by character count instead of raw bytes.
 *
 * @param source		Source string.
 * @param buffer		Destination buffer.
 * @param maxlen		Maximum size of the destination buffer.
 * @param maxChars		Maximum number of visible characters to preserve.
 */
stock void ConsolePanel_BuildUtf8TrimmedText(const char[] source, char[] buffer, int maxlen, int maxChars)
{
	int inputIndex = 0;
	int outputIndex = 0;
	int charCount = 0;
	bool truncated = false;

	while (source[inputIndex] != '\0' && outputIndex < maxlen - 1)
	{
		if (charCount >= maxChars)
		{
			truncated = true;
			break;
		}

		int charBytes = GetCharBytes(source[inputIndex]);
		if (outputIndex + charBytes >= maxlen)
		{
			truncated = true;
			break;
		}

		for (int i = 0; i < charBytes; i++)
		{
			buffer[outputIndex++] = source[inputIndex + i];
		}

		inputIndex += charBytes;
		charCount++;
	}

	if (source[inputIndex] != '\0')
	{
		truncated = true;
	}

	buffer[outputIndex] = '\0';
	if (!truncated || maxChars <= 3)
	{
		return;
	}

	StrCat(buffer, maxlen, "...");
}

/**
 * @brief Applies the panel display policy to one source string.
 *
 * Uses either console-safe ASCII output or UTF-8 trimmed output depending on panel settings.
 *
 * @param panel			Panel instance providing the display policy.
 * @param source		Source string.
 * @param buffer		Destination buffer.
 * @param maxlen		Maximum size of the destination buffer.
 * @param maxWidth		Maximum visible width in characters.
 */
stock void ConsolePanel_BuildDisplayText(ConsolePanel panel, const char[] source, char[] buffer, int maxlen, int maxWidth)
{
	if (panel.safeAsciiOnly)
	{
		ConsolePanel_BuildSafeText(source, buffer, maxlen, maxWidth);
		return;
	}

	ConsolePanel_BuildUtf8TrimmedText(source, buffer, maxlen, maxWidth);
}

/**
 * @brief Applies one line-specific display policy to a source string.
 *
 * @param line			Stored line instance providing the display policy.
 * @param source		Source string.
 * @param buffer		Destination buffer.
 * @param maxlen		Maximum size of the destination buffer.
 * @param maxWidth		Maximum visible width in characters.
 */
stock void ConsolePanelLine_BuildDisplayText(ConsolePanelLine line, const char[] source, char[] buffer, int maxlen, int maxWidth)
{
	if (line.safeAsciiOnly)
	{
		ConsolePanel_BuildSafeText(source, buffer, maxlen, maxWidth);
		return;
	}

	ConsolePanel_BuildUtf8TrimmedText(source, buffer, maxlen, maxWidth);
}

/**
 * @brief Renders one full-width border line.
 *
 * @param panel		Panel instance to render.
 * @param client		Client index to print to, or 0 for the server console.
 */
stock void ConsolePanel_PrintBorder(ConsolePanel panel, int client)
{
	char border[CONSOLE_TABLE_MAX_WIDTH + 5];
	int index = 0;

	border[index++] = '|';
	for (int i = 0; i < panel.width + 2; i++)
	{
		border[index++] = '-';
	}
	border[index++] = '|';
	border[index] = '\0';

	ConsolePanel_PrintMessage(client, border);
}

/**
 * @brief Renders one single logical line inside the panel box.
 *
 * @param panel		Panel instance to render.
 * @param client		Client index to print to, or 0 for the server console.
 * @param content		Visible line content.
 */
stock void ConsolePanel_PrintLine(ConsolePanel panel, int client, const char[] content)
{
	char display[CONSOLE_TABLE_MAX_CELL_TEXT];
	char output[CONSOLE_TABLE_MAX_WIDTH + 5];
	int index = 0;

	ConsolePanel_BuildDisplayText(panel, content, display, sizeof(display), panel.width);

	output[index++] = '|';
	output[index++] = ' ';

	int copyLength = strlen(display);
	if (copyLength > panel.width)
	{
		copyLength = panel.width;
	}

	for (int i = 0; i < copyLength; i++)
	{
		output[index++] = display[i];
	}

	while (index < panel.width + 2)
	{
		output[index++] = ' ';
	}

	output[index++] = '|';
	output[index] = '\0';
	ConsolePanel_PrintMessage(client, output);
}

/**
 * @brief Renders one single logical line that was already normalized for display.
 *
 * @param panel		Panel instance to render.
 * @param client		Client index to print to, or 0 for the server console.
 * @param content		Already-normalized visible line content.
 */
stock void ConsolePanel_PrintPreparedLine(ConsolePanel panel, int client, const char[] content)
{
	char output[CONSOLE_TABLE_MAX_WIDTH + 5];
	int index = 0;

	output[index++] = '|';
	output[index++] = ' ';

	int copyLength = strlen(content);
	if (copyLength > panel.width)
	{
		copyLength = panel.width;
	}

	for (int i = 0; i < copyLength; i++)
	{
		output[index++] = content[i];
	}

	while (index < panel.width + 2)
	{
		output[index++] = ' ';
	}

	output[index++] = '|';
	output[index] = '\0';
	ConsolePanel_PrintMessage(client, output);
}

/**
 * @brief Splits multiline text and renders each line inside the panel box.
 *
 * @param panel		Panel instance to render.
 * @param client		Client index to print to, or 0 for the server console.
 * @param content		Multiline content to split and render.
 */
stock void ConsolePanel_PrintMultiline(ConsolePanel panel, int client, const char[] content)
{
	char line[CONSOLE_TABLE_MAX_CELL_TEXT];
	int start = 0;
	int length = strlen(content);

	for (int i = 0; i <= length; i++)
	{
		if (content[i] != '\n' && content[i] != '\0')
		{
			continue;
		}

		int out = 0;
		for (int j = start; j < i && out < sizeof(line) - 1; j++)
		{
			line[out++] = content[j];
		}
		line[out] = '\0';
		ConsolePanel_PrintLine(panel, client, line);
		start = i + 1;
	}
}

/**
 * @brief Formats one typed cell into display text using the column width rules.
 *
 * @param panel			Panel instance providing the display policy.
 * @param cell			Cell value to format.
 * @param column		Column schema used for width and alignment.
 * @param buffer		Destination buffer.
 * @param maxlen		Maximum size of the destination buffer.
 */
stock void ConsoleTable_FormatCell(ConsolePanel panel, ConsoleTableCell cell, ConsoleTableColumn column, char[] buffer, int maxlen)
{
	switch (cell.type)
	{
		case ConsoleTableCellType_Int:
		{
			Format(buffer, maxlen, "%d", cell.intValue);
		}
		case ConsoleTableCellType_Float:
		{
			if (cell.floatPrecision <= 0)
			{
				Format(buffer, maxlen, "%.0f", cell.floatValue);
			}
			else if (cell.floatPrecision == 1)
			{
				Format(buffer, maxlen, "%.1f", cell.floatValue);
			}
			else if (cell.floatPrecision == 2)
			{
				Format(buffer, maxlen, "%.2f", cell.floatValue);
			}
			else
			{
				Format(buffer, maxlen, "%.3f", cell.floatValue);
			}
		}
		default:
		{
			strcopy(buffer, maxlen, cell.stringValue);
		}
	}

	char display[CONSOLE_TABLE_MAX_CELL_TEXT];
	ConsolePanel_BuildDisplayText(panel, buffer, display, sizeof(display), column.width);
	strcopy(buffer, maxlen, display);
}

/**
 * @brief Appends one aligned fragment into a row buffer.
 *
 * @param buffer		Destination row buffer.
 * @param maxlen		Maximum size of the destination buffer.
 * @param text			Visible text fragment.
 * @param width			Target width of the fragment.
 * @param alignment		Alignment mode to apply.
 */
stock void ConsoleTable_AppendAligned(char[] buffer, int maxlen, const char[] text, int width, ConsoleTableAlignment alignment)
{
	if (width <= 0)
	{
		return;
	}

	char display[CONSOLE_TABLE_MAX_CELL_TEXT];
	char formatted[CONSOLE_TABLE_MAX_CELL_TEXT];
	int textLength = strlen(text);
	int copyLength = textLength;
	if (copyLength > width)
	{
		copyLength = width;
	}

	for (int i = 0; i < copyLength && i < sizeof(display) - 1; i++)
	{
		display[i] = text[i];
	}
	display[copyLength] = '\0';

	int leftPadding = 0;
	int rightPadding = 0;
	int remaining = width - copyLength;
	if (remaining < 0)
	{
		remaining = 0;
	}

	switch (alignment)
	{
		case ConsoleTableAlignment_Right:
		{
			leftPadding = remaining;
		}
		case ConsoleTableAlignment_Center:
		{
			leftPadding = remaining / 2;
			rightPadding = remaining - leftPadding;
		}
		default:
		{
			rightPadding = remaining;
		}
	}

	int index = 0;
	for (int i = 0; i < leftPadding && index < sizeof(formatted) - 1; i++)
	{
		formatted[index++] = ' ';
	}

	for (int i = 0; display[i] != '\0' && index < sizeof(formatted) - 1; i++)
	{
		formatted[index++] = display[i];
	}

	for (int i = 0; i < rightPadding && index < sizeof(formatted) - 1; i++)
	{
		formatted[index++] = ' ';
	}

	while (index < width && index < sizeof(formatted) - 1)
	{
		formatted[index++] = ' ';
	}

	formatted[index] = '\0';

	StrCat(buffer, maxlen, formatted);
}

/**
 * @brief Builds the header row from the current table schema.
 *
 * @param panel			Panel instance containing the table schema.
 * @param buffer		Destination row buffer.
 * @param maxlen		Maximum size of the destination buffer.
 */
stock void ConsoleTable_BuildHeaderRow(ConsolePanel panel, char[] buffer, int maxlen)
{
	buffer[0] = '\0';
	for (int columnIndex = 0; columnIndex < panel.table.columnCount; columnIndex++)
	{
		if (columnIndex > 0)
		{
			StrCat(buffer, maxlen, " | ");
		}

		ConsoleTable_AppendAligned(buffer, maxlen, panel.table.columns[columnIndex].title, panel.table.columns[columnIndex].width, panel.table.columns[columnIndex].alignment);
	}
}

/**
 * @brief Builds one rendered body row from typed cell data.
 *
 * @param panel			Panel instance containing the row data.
 * @param rowIndex		Zero-based row index to format.
 * @param buffer		Destination row buffer.
 * @param maxlen		Maximum size of the destination buffer.
 */
stock void ConsoleTable_BuildRow(ConsolePanel panel, int rowIndex, char[] buffer, int maxlen)
{
	buffer[0] = '\0';

	for (int columnIndex = 0; columnIndex < panel.table.columnCount; columnIndex++)
	{
		if (columnIndex > 0)
		{
			StrCat(buffer, maxlen, " | ");
		}

		char cellText[CONSOLE_TABLE_MAX_CELL_TEXT];
		cellText[0] = '\0';

		if (columnIndex < panel.table.rows[rowIndex].cellCount)
		{
			ConsoleTable_FormatCell(panel, panel.table.rows[rowIndex].cells[columnIndex], panel.table.columns[columnIndex], cellText, sizeof(cellText));
		}

		ConsoleTable_AppendAligned(buffer, maxlen, cellText, panel.table.columns[columnIndex].width, panel.table.columns[columnIndex].alignment);
	}
}

/**
 * @brief Validates that the table schema fits within the configured panel width.
 *
 * @param panel		Panel instance to validate.
 * @return			True if the table fits within the panel width, false otherwise.
 */
stock bool ConsoleTable_ValidateWidth(ConsolePanel panel)
{
	int totalWidth = 0;
	for (int columnIndex = 0; columnIndex < panel.table.columnCount; columnIndex++)
	{
		totalWidth += panel.table.columns[columnIndex].width;
		if (columnIndex > 0)
		{
			totalWidth += 3;
		}
	}

	return totalWidth <= panel.width;
}

/**
 * @brief Renders the full panel to one target console.
 *
 * @param panel		Panel instance to render.
 * @param client		Client index to print to, or 0 for the server console.
 */
stock void ConsolePanel_RenderToClient(ConsolePanel panel, int client)
{
	char row[CONSOLE_TABLE_MAX_CELL_TEXT];
	ConsolePanel_PrintBorder(panel, client);

	for (int index = 0; index < panel.headerLineCount; index++)
	{
		char display[CONSOLE_TABLE_MAX_CELL_TEXT];
		ConsolePanelLine_BuildDisplayText(panel.headerLines[index], panel.headerLines[index].text, display, sizeof(display), panel.width);
		ConsolePanel_PrintPreparedLine(panel, client, display);
	}

	if (panel.headerLineCount > 0)
	{
		ConsolePanel_PrintBorder(panel, client);
	}

	if (panel.table.columnCount > 0)
	{
		ConsoleTable_BuildHeaderRow(panel, row, sizeof(row));
		ConsolePanel_PrintLine(panel, client, row);
		ConsolePanel_PrintBorder(panel, client);

		if (!ConsoleTable_ValidateWidth(panel))
		{
			ConsolePanel_PrintLine(panel, client, "Table width exceeds panel width.");
		}
		else
		{
			for (int rowIndex = 0; rowIndex < panel.table.rowCount; rowIndex++)
			{
				ConsoleTable_BuildRow(panel, rowIndex, row, sizeof(row));
				ConsolePanel_PrintLine(panel, client, row);
			}
		}

		if (panel.footerLineCount > 0)
		{
			ConsolePanel_PrintBorder(panel, client);
		}
	}

	for (int index = 0; index < panel.footerLineCount; index++)
	{
		char display[CONSOLE_TABLE_MAX_CELL_TEXT];
		ConsolePanelLine_BuildDisplayText(panel.footerLines[index], panel.footerLines[index].text, display, sizeof(display), panel.width);
		ConsolePanel_PrintPreparedLine(panel, client, display);
	}

	ConsolePanel_PrintBorder(panel, client);
}

/**
 * @brief Renders the same panel to every in-game human except the excluded client.
 *
 * @param panel				Panel instance to render.
 * @param excludedClient	Client index to skip when broadcasting the panel.
 */
stock void ConsolePanel_RenderToAudience(ConsolePanel panel, int excludedClient = 0)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (client == excludedClient)
		{
			continue;
		}

		if (!IsClientInGame(client) || IsFakeClient(client))
		{
			continue;
		}

		ConsolePanel_RenderToClient(panel, client);
	}
}
