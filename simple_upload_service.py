#!/usr/bin/env python3
"""
简化的上传服务 - 只保留base64上传和rclone listremotes功能
"""

import os
import base64
import subprocess
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)  # 允许跨域请求

class RcloneUploader:
    """rclone上传器"""
    
    
    def upload_with_rclone(self, local_file: str, remote_path: str) -> dict:
        """使用rclone上传文件"""
        try:
            # 构建rclone命令
            cmd = ['rclone', 'copyto', local_file, remote_path, '--progress']
            
            print(f"执行命令: {' '.join(cmd)}")
            
            # 执行上传命令
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            
            if result.returncode == 0:
                return {
                    'success': True,
                    'message': f'文件 {local_file} 上传到 {remote_path} 成功',
                    'command': ' '.join(cmd)
                }
            else:
                return {
                    'success': False,
                    'message': f'上传失败: {result.stderr}',
                    'command': ' '.join(cmd),
                    'error': result.stderr
                }
                
        except subprocess.TimeoutExpired:
            return {
                'success': False,
                'message': '上传超时（超过5分钟）',
                'command': ' '.join(cmd)
            }
        except Exception as e:
            return {
                'success': False,
                'message': f'上传异常: {str(e)}',
                'command': ' '.join(cmd)
            }

# 全局实例
rclone_uploader = RcloneUploader()

@app.route('/api/upload-base64', methods=['POST'])
def upload_base64_task():
    """接收base64编码的任务文件并直接上传到rclone"""
    try:
        data = request.json
        
        # 验证必需字段
        required_fields = ['base64Content', 'destPath']
        for field in required_fields:
            if not data.get(field):
                return jsonify({'error': f'{field} 不能为空'}), 400
        
        base64_content = data['base64Content']
        dest_path = data['destPath']
        filename = data.get('filename', 'uploaded.task')
        
        # base64解码
        try:
            decoded_content = base64.b64decode(base64_content).decode('utf-8')
        except Exception as e:
            return jsonify({'error': f'base64解码失败: {str(e)}'}), 400
        
        # 保存临时文件
        temp_dir = '/tmp/simple_upload'
        os.makedirs(temp_dir, exist_ok=True)
        
        local_file = os.path.join(temp_dir, filename)
        with open(local_file, 'w', encoding='utf-8') as f:
            f.write(decoded_content)
        
        # 构建完整的远程路径
        if ':' in dest_path:
            parts = dest_path.split(':', 1)
            bucket = parts[0]
            remote_path = parts[1].rstrip('/') if parts[1] else ''
            
            if remote_path:
                remote_full_path = f"{bucket}:{remote_path}/{filename}"
            else:
                remote_full_path = f"{bucket}:{filename}"
        else:
            remote_full_path = f"jdcloud:tasks/pending/{filename}"
        
        # 使用rclone上传
        result = rclone_uploader.upload_with_rclone(local_file, remote_full_path)
        
        # 清理临时文件
        try:
            os.remove(local_file)
        except:
            pass
        
        return jsonify(result)
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/rclone-listremotes', methods=['GET'])
def get_rclone_listremotes():
    """直接返回rclone listremotes内容"""
    try:
        result = subprocess.run(['rclone', 'listremotes'], 
                              capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            listremotes_output = result.stdout.strip()
            remotes = [line.rstrip(':') for line in listremotes_output.split('\n') if line.strip()]
            
            return jsonify({
                'success': True,
                'remotes': remotes,
                'count': len(remotes)
            })
        else:
            return jsonify({
                'success': False,
                'error': result.stderr,
                'return_code': result.returncode
            }), 500
            
    except subprocess.TimeoutExpired:
        return jsonify({
            'success': False,
            'error': '命令执行超时'
        }), 500
    except FileNotFoundError:
        return jsonify({
            'success': False,
            'error': 'rclone命令未找到，请确保rclone已安装'
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500



if __name__ == '__main__':
    print("🔧 FFRmt Client")
    print("API端点:")
    print("  POST /api/upload-base64 - base64编码上传")
    print("  GET  /api/rclone-listremotes - 获取rclone listremotes内容")
    print("")
    
    
    print("\n🚀 服务运行在 http://localhost:5002")
    app.run(host='127.0.0.1', port=5002, debug=True)