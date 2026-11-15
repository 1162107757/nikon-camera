# A面板真实失败attempt（原件）

这是post-614、ed冻结前的夹具修正阶段，结果为 0/1，另有5项未完成；不是整文件通过，不叠加到通过总数。原qualification、result、日志、对应test源码和runner按字节复制，见archive-byte-manifest.json。

duplicate-text原attempt的RAW文案在底层面板和确认Dialog各出现一次，未限定Dialog导致exact-one断言失败；随后Windows native AV，剩余5项零完成。修法仍保exact-one，只限定真实Dialog范围。stop-phase原attempt5/1的active/working先释放，但异步stop仍处于stopping阶段，格式正确保持锁定；修法等待真正stopped再保留原解锁断言。

最终ed候选的A整文件6/0独立存于shared，原失败不回写为通过。没有为归档重跑、修改产品/门禁或发布。
