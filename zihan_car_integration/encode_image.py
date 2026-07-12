"""
encode_image.py

这是一个辅助脚本，用于将本地图片文件编码为 Base64 字符串。
编码后的字符串可用于通过 API 接口（如 /register-face 或 /process-video）
向后端服务发送图片数据，而无需处理文件上传。

此版本支持将 Base64 字符串输出到文件，以避免终端复制粘贴长字符串的问题。

用法：
1. 运行此脚本。
2. 输入本地图片文件的完整路径。
3. 可选择输入一个输出文件路径（例如 output.txt），Base64 字符串将保存到该文件。
4. 脚本将打印出 Base64 编码的字符串到终端，如果指定了输出文件，也会保存到文件。
"""

import base64
import os

def image_to_base64(image_path: str) -> str | None:
    """
    将指定路径的图片文件读取并编码为 Base64 字符串。
    如果文件不存在或无法读取，返回 None。
    """
    if not os.path.exists(image_path):
        print(f"错误: 图像文件未找到: {image_path}")
        return None
    
    try:
        with open(image_path, "rb") as image_file:
            # 读取文件内容，然后进行 Base64 编码，并解码为 UTF-8 字符串
            encoded_string = base64.b64encode(image_file.read()).decode('utf-8')
        return encoded_string
    except Exception as e:
        print(f"错误: 编码图像失败。详情: {e}")
        return None

if __name__ == "__main__":
    print(">>> Base64 图像编码工具 <<<")
    print("此工具将本地图片转换为 Base64 字符串，可选择保存到文件。")
    
    # 循环直到用户输入有效路径或选择退出
    while True:
        input_path = input("请输入图片文件的完整路径 (例如: D:/path/to/my_face.jpg)。输入 'q' 退出: ").strip()

        if input_path.lower() == 'q':
            print("用户退出。")
            break

        # 在 Windows 上，用户可能会粘贴反斜杠路径。将其转换为正斜杠。
        if os.sep == '\\': # Check if running on Windows
            input_path = input_path.replace('\\', '/')

        base64_data = image_to_base64(input_path)

        if base64_data:
            print("\n--- Base64 编码图像数据 ---")
            print("（如果字符串过长，建议从文件中复制）")
            print(base64_data)
            print("---------------------------\n")

            # 询问是否保存到文件
            save_to_file = input("是否将此 Base64 字符串保存到文件？(y/n): ").strip().lower()
            if save_to_file == 'y':
                output_file_path = input("请输入输出文件的完整路径和文件名 (例如: D:/temp/base64_output.txt): ").strip()
                if os.sep == '\\':
                    output_file_path = output_file_path.replace('\\', '/')
                
                try:
                    with open(output_file_path, "w") as f:
                        f.write(base64_data)
                    print(f"Base64 字符串已成功保存到: {output_file_path}\n")
                except Exception as e:
                    print(f"错误: 无法保存到文件。详情: {e}\n")
            
            # 成功编码并处理后，询问是否继续
            continue_encoding = input("是否继续编码其他图片？(y/n): ").strip().lower()
            if continue_encoding != 'y':
                break
        else:
            print("请检查图片路径是否正确，或文件是否可读。")