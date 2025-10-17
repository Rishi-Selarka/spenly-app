# Receipt Scan Feature - Debug Guide

## What I Added

I've added extensive logging to trace the entire receipt scanning flow. When you scan a receipt, you'll see detailed console output showing exactly what's happening.

## How to Debug

1. **Open Xcode Console** (⌘+⇧+C) to see logs
2. **Scan a receipt** using the paperclip button → "Scan Receipt"
3. **Watch for these log markers:**

### Expected Log Flow (Success):

```
📸 Starting receipt scan...
✅ Gemini response received:
[{"amount":45.99,"isExpense":true,"note":"Groceries","category":"Food","date":"2025-01-15"}]
🔍 Attempting to parse LLM text...
✅ Strategy 1 succeeded (direct JSON array)
✅ Parsed 1 draft(s)
```

### If It Fails, You'll See:

**API Error:**
```
📸 Starting receipt scan...
❌ Gemini API error: [error message]
```

**Parsing Error:**
```
✅ Gemini response received:
[response text will be shown here]
🔍 Attempting to parse LLM text...
❌ All parsing strategies failed
❌ Failed to parse drafts from response
```

## Common Issues & Fixes

### Issue 1: "Receipt scan failed: invalid response"
**Cause:** Gemini API returned unexpected structure
**Fix:** Check the raw response in console. The response should contain a JSON array.

### Issue 2: "Could not confidently read receipt"
**Possible Causes:**
1. **Gemini returned prose instead of JSON**
   - Look at the console output after "✅ Gemini response received:"
   - If you see text like "I can see this is a receipt..." instead of JSON, the prompt isn't working
   
2. **JSON is malformed**
   - Look for syntax errors in the JSON output
   - Common: missing quotes, trailing commas, invalid date formats
   
3. **Amount parsing failed**
   - Look for "⚠️ Could not parse amount from: [value]"
   - This means the amount field is missing or in wrong format

### Issue 3: Image Upload Issues
**Symptoms:** Error immediately after taking photo
**Check:** 
- Is the image too large? (Should compress to 75% automatically)
- Is the Gemini API key valid?

## Manual Testing

Send me the **exact console output** including:
1. The line starting with "✅ Gemini response received:"
2. All following lines until you see "❌" or "✅ Parsed X draft(s)"

This will tell me exactly what the AI is returning and why parsing is failing.

## Key Implementation Details

### Parsing Strategies (in order):

1. **Direct JSON Array** - Looks for `[{...}]` in the response
2. **Fenced Code Blocks** - Extracts JSON from ``` code blocks
3. **Permissive Mapping** - Handles:
   - Plain array: `[{"amount": 10}]`
   - Wrapped object: `{"transactions": [{"amount": 10}]}`
   - String amounts: `"$10.99"` → `10.99`
   - Type field: `"type": "income"` → `isExpense: false`
   - Multiple date formats: ISO8601, yyyy-MM-dd, MM/dd/yyyy, etc.

### What the AI Should Return:

```json
[
  {
    "amount": 45.99,
    "isExpense": true,
    "note": "Groceries",
    "category": "Food & Dining",
    "date": "2025-01-15"
  }
]
```

Or with nullable date:
```json
[
  {
    "amount": 45.99,
    "isExpense": true,
    "note": "Groceries",
    "category": "Food & Dining",
    "date": null
  }
]
```

## Next Steps

1. **Test with a real receipt** and share the console output
2. I'll analyze what Gemini is actually returning
3. We'll adjust the:
   - Prompt instructions (if AI isn't following format)
   - Parsing logic (if response format is different)
   - Error messages (to be more helpful)

## Files Modified

- `Spenly/Views/SpenlyChatView.swift` - Added logging to parsing flow
- `Spenly/Managers/GeminiManager.swift` - Fixed API request structure
- `Spenly/Models/DraftTransaction.swift` - Transaction draft model
- `Spenly/Views/ImportConfirmationView.swift` - Confirmation UI
- `Spenly/Utilities/JSONDecoder+ISO8601.swift` - Date decoding helper

