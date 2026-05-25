%% 将16bit灰度RAW图片转为txt 以供modelsim读取
clc;
clear all;

%% 参数设置（根据你的RAW图像实际大小修改）
image_width = 640;   % 图像宽度
image_height = 480;  % 图像高度

%% 读取RAW图像文件
file_read_id = fopen('test_img.raw', 'r');


% 以 uint16 格式读取二进制流
raw_data = fread(file_read_id, image_width * image_height, 'uint16=>uint16');
fclose(file_read_id);

% 恢复为二维灰度图像矩阵（转置以匹配行优先的扫描顺序）
image_gray = reshape(raw_data, [image_width, image_height])';

%% 显示图像
% 使用 [] 自动拉伸 16bit 灰度对比度，防止显示全黑
imshow(image_gray, []);
title('读取的16位灰度RAW原图');

%% 打开文件以写入txt
file_write_id = fopen('raw.txt', 'w+'); 

%% 遍历每一个像素并写入到文件中
for row_index = 1:image_height
    for col_index = 1:image_width 
        % 将每个 16bit 像素值写入文件，以 4 位十六进制格式表示（对应 16 位宽）
        fprintf(file_write_id, '%04x', image_gray(row_index, col_index));
        % 每行像素结束后换行
        fprintf(file_write_id, '\n');
    end
end

%% 关闭文件
fclose(file_write_id);