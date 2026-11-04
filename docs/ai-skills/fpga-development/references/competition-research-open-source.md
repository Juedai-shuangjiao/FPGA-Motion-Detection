# 竞赛竞品调研与开源发布规范（嵌入式FPGA创新设计赛道）

## 比赛背景（2026 第九届，确定性信息）

- 全名：第九届（2026）全国大学生嵌入式芯片与系统设计竞赛 FPGA 创新设计赛道；官网 www.fpgachina.cn（报名/通知），另参考 www.socchina.net；协办企业含安路、高云、紫光同创、易灵思等，各企业有独立选题指南。
- 时间线：作品提交 2026-11-04 18:00；决赛 2026-11-20~22，地点南京江北新区。获奖证书按组队顺序制作；组委会与队伍共同拥有作品文档/视频发布权（开源不冲突）。
- 决赛现场有 FPGA 基础编程能力考核，通过才有评奖资格。

## GitHub 竞品调研方法（curl 即可，不需要网页）

1. 仓库搜索：`curl -s "https://api.github.com/search/repositories?q=<板卡型号>&sort=updated&order=desc"`——板卡型号（如 HX1P35A）是比芯片型号更好的关键词（竞赛专用板，仓库少而精）。结果按 updated 排序，比赛提交前 1~2 周是集中爆发期。
2. 仓库详情：`api.github.com/repos/<owner>/<repo>`（stars/forks/language/pushed_at）；用户信息：`api.github.com/users/<login>`——**竞赛队多为比赛专用新号（匿名 noreply 邮箱、无 location/bio），查学校通常无果，如实告知用户即可，别过度深挖身份**。
3. README 抓取：`raw.githubusercontent.com/<owner>/<repo>/main/README.md`（分支不一定是 main，先 API 查 default_branch）。
4. 深挖结构：clone --depth 1 后 find 源码树、grep 目标模块；对方 tb 命名（tb_<模块>_<关注点>）是找验证思路的入口。
5. 竞品仓库清单（HX1P35A 赛道，2026-10 快照）：jkoksnsnjs-arch/fpga-vision-hx1p35a（SC500CS+DDR2+HDMI720P，运动检测/颜色形状识别/数字识别，仓库结构最规范）、Dexter4real/anlogic-s2-image-system（赛题二图像增强）、mkleo123/FPGA_HX1P35A-PH1P35-、touch0721/fpga-hx1p35a、xiaozehao3/hx1p35a-sc520cs-vision、XXX06C10/vision_follow_20261022。同板参考工程另见 sc500-resolution-config.md 的 Cirbug/sc500cs 条目。

## 竞品工程方法论（可借鉴的规范动作）

- 测试自动化：tb 用缩小图（128×96）喂确定性刺激 + 断言式 PASS/FAIL，ModelSim 全量 + XSim 补充双工具链，FAIL 即终止、不以旧日志替代新结果；results/ 存全部仿真日志。
- 构建：build_syn.tcl / build_phy.tcl 两个独立脚本分开跑（各自结束会话），脚本路径用绝对路径启动。
- 发布：release/ 放正式 bit + SHA256；提交版本号命名（如 frame_seg_20261021）；docs/REPRODUCTION.md 写从仿真到烧录的完整复现步骤；scripts/verify_submission.py 提交前自动核对清单。
- 运动检测参考架构（hdmi_mixer 内 motion_tile_detector + motion_frame_bank）：8×8 块网格（1280×720→160×90=14400 块），块特征 = 平均亮度 + 亮度空间矩（signed moments，能检出均值不变但内部移动）+ 颜色分类；帧间三条件判运动（亮度差超阈/颜色类翻转/空间矩变化）；双区域流式连通域 + 正/负移动边缘配对（平移物体左右边界一正一负才合并）+ 与上帧输出框重叠判定维持目标身份；帧存单块 RAM 同地址先读旧值再写新值省一半存储。用户做「外接框+质心+跟踪」的身份关联逻辑可直接参考此结构。

## 加密 IP 的开源处理规范（照抄对方，经三方哈希验证无风险）

- **安路加密 IP（.enc.v，IEEE 1735 pragma protect + base64 密文）原样入库**：不解密、不转格式、保持原始字节——编译时 TD 凭本地授权处理，无密钥者拿到也编译不了，比赛评审/开源社区默认接受。
- **验证「官方例程 = 用户工程 = 对方仓库」三方 sha256 一致后，照抄对方处理方式零风险**：竞赛板 IP 本就随例程分发，每队工程里是同一份。
- 配套规范三件套（都放仓库）：①docs/THIRD_PARTY.md 声明（明文写清「加密 IP 保持原始字节、不解密」「不附带 TD 安装包/许可证/器件库/破解文件」「第三方源码沿用各自原声明，不统一套 MIT」）；②manifests/imported_files.json 记每个导入文件的 original_sha256 vs 当前 sha256（哈希证据证明加密 IP 原样未动）；③manifests/files.json 全仓库文件 SHA256 清单（提交完整性校验）。.params/.m_params/.ports/IP-XACT 是生成参数或接口描述，不算缓存可留。
- 明文 IP（PLL/FIFO/RAM 等 TD 生成的 .v）入库无敏感。
- 时机：比赛提交（11-04）前暂不开源自己方案，提交后照此模板发。