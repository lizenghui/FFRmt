import os
import sys
import argparse
from google import genai


MODEL_NAME = "gemini-2.5-flash"  # 与您的 test.py 保持一致

import logging
from datetime import datetime

def setup_logging(log_file_path):
    """设置Python标准日志系统"""
    # 创建logger
    logger = logging.getLogger('fix_ffmpeg')
    logger.setLevel(logging.INFO)
    
    # 创建文件处理器
    file_handler = logging.FileHandler(log_file_path, encoding='utf-8')
    file_handler.setLevel(logging.INFO)
    
    # 创建格式化器
    formatter = logging.Formatter('[%(asctime)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
    file_handler.setFormatter(formatter)
    
    # 添加处理器到logger
    logger.addHandler(file_handler)
    
    return logger

def log_message(message, logger=None):
    """使用标准日志系统记录消息"""
    if logger:
        logger.info(message)
    else:
        # 备用方案：输出到stderr
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {message}", file=sys.stderr)

def generate_prompt(original_command, ffmpeg_log):
    """
    为 AI 创建一个详细的、用于修正 ffmpeg 命令的 Prompt。
    (此函数无需改变)
    """
    return f"""
你是一位精通 FFmpeg 的专家。你的任务是根据失败的 FFmpeg 命令及其错误日志，来修正这条命令。

**1. 失败的原始 FFmpeg 命令:**
```bash
{original_command}
```

**2. FFmpeg 错误日志:**
```
{ffmpeg_log}
```

**3. 你的任务:**
请仔细分析原始命令和错误日志，找出失败的根本原因。
然后，提供一个修正后的 FFmpeg 命令，确保它能成功执行。

**!!! 重要指令:**
- **只输出**修正后的、单行的 FFmpeg 命令本身。
- **不要**包含任何解释、注释或 "这是修正后的命令：" 之类的描述性文字。
- 确保命令是干净的单行文本。
- 如果你无法确定如何修复，请原样返回原始命令。
"""

def fix_ffmpeg_command(original_command, ffmpeg_log):
    """
    使用 genai.Client() 接口为 ffmpeg 命令提供修复建议。
    """
    try:
        # 初始化客户端。它会根据环境自动处理身份验证。
        client = genai.Client()

        prompt = generate_prompt(original_command, ffmpeg_log)
        
        # 使用 client.models.generate_content 方法
        response = client.models.generate_content(
            model=MODEL_NAME,
            contents=prompt
        )

        # 清理AI返回的文本，确保它只是一个命令
        corrected_command = response.text.strip()
        
        # 进一步清理，移除可能的Markdown代码块标记
        if corrected_command.startswith("```") and corrected_command.endswith("```"):
            corrected_command = '\n'.join(corrected_command.split('\n')[1:-1]).strip()

        # 一个基础检查，看返回的是否像一个正常的命令
        if not corrected_command or not corrected_command.lower().startswith("ffmpeg"):
            log_message(f"警告: AI 返回了非预期的内容: '{corrected_command}'")
            return original_command

        return corrected_command

    except Exception as e:
        log_message(f"调用 AI API 时发生错误: {e}")
        log_message("请确保您的环境已通过 'gcloud auth application-default login' 或其他方式正确认证。")
        return original_command

def main():
    """
    主函数，用于解析命令行参数并执行命令修正。
    (此函数无需改变)
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

    args = parser.parse_args()

    # 生成fix.log文件路径（在相同目录下）
    fix_log_file = os.path.join(os.path.dirname(args.log_file), "fix.log")
    
    # 设置日志系统
    logger = setup_logging(fix_log_file)
    
    log_message(f"开始修复FFmpeg命令", logger)
    log_message(f"原始命令: {args.command}", logger)

    try:
        with open(args.log_file, 'r', encoding='utf-8') as f:
            log_content = f.read()
        log_message(f"成功读取错误日志: {args.log_file}", logger)
    except FileNotFoundError:
        log_message(f"错误: 日志文件未找到 {args.log_file}", logger)
        # 即使失败也输出原始命令
        sys.stdout.write(args.command)
        sys.stdout.flush()
        sys.exit(1)
    except Exception as e:
        log_message(f"读取日志文件时出错: {e}", logger)
        # 即使失败也输出原始命令
        sys.stdout.write(args.command)
        sys.stdout.flush()
        sys.exit(1)

    log_message("开始调用AI进行命令修复", logger)
    corrected_command = fix_ffmpeg_command(args.command, log_content)
    log_message(f"修复完成，返回命令: {corrected_command}", logger)

    if corrected_command:
        # 确保只输出命令本身，没有其他内容
        sys.stdout.write(corrected_command)
        sys.stdout.flush()
        log_message("成功输出修复后的命令", logger)
    else:
        # 如果修正失败，输出原始命令
        sys.stdout.write(args.command)
        sys.stdout.flush()
        log_message("修复失败，输出原始命令", logger)

if __name__ == "__main__":
    main()