# 音乐搜索验证样例集

## 评分标准

- `命中`
  - 前 3 条内出现目标歌曲或明显正确版本
- `弱命中`
  - 前 5 条内出现目标歌曲，但排序不理想
- `未命中`
  - 前 5 条内没有明显正确结果
- `可播`
  - 结果可直接站内播放
- `仅预览`
  - 结果只有预览音频
- `仅索引`
  - 结果只能外部打开或查看详情

## 样例分组

### 中文歌名

- `晴天`
- `稻香`
- `夜曲`
- `后来`

### 英文歌名

- `Shape of You`
- `Blinding Lights`
- `Someone Like You`
- `Yellow`

### 歌手名

- `周杰伦`
- `Adele`
- `Coldplay`
- `Taylor Swift`

### 歌手 + 歌名

- `周杰伦 - 晴天`
- `Adele - Hello`
- `Coldplay Yellow`
- `Taylor Swift Love Story`

### 模糊或别名输入

- `jay chou qing tian`
- `adele hello live`
- `coldplay yellow acoustic`
- `love story taylor`

### 长尾或版本词

- `Mojito 周杰伦`
- `Rolling in the Deep remix`
- `Fix You live`
- `青花瓷 cover`

## 验证记录建议

每次改动后，至少记录以下信息：

- 查询词
- 前 3 条结果标题
- 是否命中
- 是否可播
- 主要来源分布
- 是否存在重复结果

## 验证优先顺序

- 先验证 `歌手 + 歌名`
- 再验证纯歌名
- 再验证版本词和模糊输入
- 最后验证长尾内容
