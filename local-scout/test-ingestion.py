from markitdown import MarkItDown

md = MarkItDown()
print('Alpha Local Scout ingestion layer is installed.')
print('Test a public file or YouTube URL with:')
print("result = md.convert('https://www.youtube.com/watch?v=VIDEO_ID')")
print('print(result.text_content[:2000])')
