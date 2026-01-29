import os
import sys
import argparse
import google.generativeai as genai

# --- 配置 ---
# 重要：强烈建议通过环境变量来设置API密钥，以确保安全。
# 例如: export GEMINI_API_KEY="your_api_key"
API_KEY = os.environ.get("GEMINI_API_KEY")
MODEL_NAME = "gemini-1.5-flash"  # 您也可以选择其他合适的模型

def generate_prompt(original_command, ffmpeg_log, intent):
    """
    为 AI 创建一个详细的、用于修正 ffmpeg 命令的 Prompt。
    """
    return f"""
你是一位精通 FFmpeg 的专家。你的任务是根据失败的 FFmpeg 命令、其错误日志以及用户的原始意图，来修正这条命令。

**1. 用户的原始意图:**
用户希望执行的操作是：“{intent}”

**2. 失败的原始 FFmpeg 命令:**
```bash
{original_command}
```

**3. FFmpeg 错误日志:**
```
{ffmpeg_log}
```

**4. 你的任务:**
请仔细分析原始命令和错误日志，找出失败的根本原因。
然后，提供一个修正后的 FFmpeg 命令，确保它能成功实现用户的原始意图。

**!!! 重要指令:**
- **只输出**修正后的、单行的 FFmpeg 命令本身。
- **不要**包含任何解释、注释或 "这是修正后的命令：" 之类的描述性文字。
- 确保命令是干净的单行文本。
- 如果你无法确定如何修复，请原样返回原始命令。
"""

def fix_ffmpeg_command(original_command, ffmpeg_log, intent):
    """
    调用 Gemini AI 来为 ffmpeg 命令提供修复建议。
    """
    if not API_KEY:
        print("错误: 环境变量 GEMINI_API_KEY 未设置。", file=sys.stderr)
        return original_command  # 返回原始命令以避免中断流程

    try:
        genai.configure(api_key=API_KEY)
        model = genai.GenerativeModel(MODEL_NAME)

        prompt = generate_prompt(original_command, ffmpeg_log, intent)
        
        # 调用模型生成内容
        response = model.generate_content(prompt)

        # 清理AI返回的文本，确保它只是一个命令
        corrected_command = response.text.strip()
        
        # 进一步清理，移除可能的Markdown代码块标记
        if corrected_command.startswith("```") and corrected_command.endswith("```"):
            # 取出被 ```bash ... ``` 包裹的内容
            corrected_command = '\n'.join(corrected_command.split('\n')[1:-1]).strip()

        # 一个基础检查，看返回的是否像一个正常的命令
        if not corrected_command or not corrected_command.lower().startswith("ffmpeg"):
            print(f"警告: AI 返回了非预期的内容: '{corrected_command}'", file=sys.stderr)
            return original_command  # 如果返回内容很奇怪，则返回原始命令

        return corrected_command

    except Exception as e:
        print(f"调用 AI API 时发生错误: {e}", file=sys.stderr)
        return original_command # 出现异常时也返回原始命令

def main():
    """
    主函数，用于解析命令行参数并执行命令修正。
    """
    parser = argparse.ArgumentParser(
        description="使用 AI 修正失败的 FFmpeg 命令。"
    )
    parser.add_argument(
        "--command",
        required=True,
        help="原始的、执行失败的 FFmpeg 命令字符串。"
    )
    parser.add_argument(
        "--log-file",
        required=True,
        help="FFmpeg 错误日志文件的路径。"
    )
    parser.add_argument(
        "--intent",
        required=True,
        help="对原始命令意图的文字描述。"
    )

    args = parser.parse_args()

    try:
        with open(args.log_file, 'r', encoding='utf-8') as f:
            log_content = f.read()
    except FileNotFoundError:
        print(f"错误: 日志文件未找到 {args.log_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"读取日志文件时出错: {e}", file=sys.stderr)
        sys.exit(1)

    corrected_command = fix_ffmpeg_command(args.command, log_content, args.intent)

    if corrected_command:
        print(corrected_command)
    else:
        # 如果修正失败，也打印原始命令，以便让调用它的脚本继续执行或处理失败
        print(args.command)
        sys.exit(1)

if __name__ == "__main__":
    main()
