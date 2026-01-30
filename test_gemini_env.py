import os
import sys
from google import genai

MODEL_NAME = "gemini-2.5-flash"

def test_gemini():
    try:
        client = genai.Client()

        response = client.models.generate_content(
      	    model=MODEL_NAME,
      	    contents='你好，你是一个什么模型？用中文简洁地回答。'
        )

        print("\n--- Gemini 响应 ---")
        print(response.text)
        print("--- 测试成功 ---")

    except Exception as e:
        print(f"\n--- 测试失败 ---", file=sys.stderr)
        print(f"连接 Gemini API 时发生错误: {e}", file=sys.stderr)
        print("请检查您的 API 密钥是否正确，以及网络连接是否正常。", file=sys.stderr)
        sys.stderr.flush() # Ensure error message is flushed
        sys.exit(1)

if __name__ == "__main__":
    test_gemini()
