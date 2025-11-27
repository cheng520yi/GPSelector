import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/favorite_group.dart';
import '../services/favorite_group_service.dart';

class FavoriteGroupEditScreen extends StatefulWidget {
  const FavoriteGroupEditScreen({super.key});

  @override
  State<FavoriteGroupEditScreen> createState() => _FavoriteGroupEditScreenState();
}

class _FavoriteGroupEditScreenState extends State<FavoriteGroupEditScreen> {
  List<FavoriteGroup> _groups = [];
  bool _isLoading = false;

  // 预设颜色列表
  static const List<Color> _presetColors = [
    Colors.black,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final groups = await FavoriteGroupService.getAllGroups();
      setState(() {
        _groups = groups;
      });
    } catch (e) {
      print('加载分组失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createNewGroup() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '分组名称',
            hintText: '请输入分组名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.of(context).pop(nameController.text.trim());
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null) {
      final newGroup = await FavoriteGroupService.createGroup(name: result);
      if (newGroup != null) {
        _loadGroups();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分组创建成功')),
        );
      }
    }
  }

  Future<void> _deleteGroup(FavoriteGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除分组"${group.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FavoriteGroupService.deleteGroup(group.id);
      _loadGroups();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('分组已删除')),
      );
    }
  }

  Future<void> _editGroupName(FavoriteGroup group) async {
    final nameController = TextEditingController(text: group.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑分组名称'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '分组名称',
            hintText: '请输入分组名称',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                Navigator.of(context).pop(nameController.text.trim());
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (result != null && result != group.name) {
      final updatedGroup = group.copyWith(name: result);
      await FavoriteGroupService.updateGroup(updatedGroup);
      _loadGroups();
    }
  }

  Future<void> _selectColor(FavoriteGroup group) async {
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择颜色'),
        content: SizedBox(
          width: double.maxFinite,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _presetColors.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                // 无颜色选项
                return InkWell(
                  onTap: () => Navigator.of(context).pop(null),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('无'),
                    ),
                  ),
                );
              }
              final color = _presetColors[index - 1];
              final isSelected = group.color != null &&
                  _colorToHex(color) == group.color;
              return InkWell(
                onTap: () => Navigator.of(context).pop(color),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(color: Colors.black, width: 3)
                        : null,
                  ),
                  child: isSelected
                      ? const Center(
                          child: Icon(Icons.check, color: Colors.white),
                        )
                      : null,
                ),
              );
            },
          ),
        ),
      ),
    );

    if (selectedColor != null) {
      final colorHex = _colorToHex(selectedColor);
      final updatedGroup = group.copyWith(color: colorHex);
      await FavoriteGroupService.updateGroup(updatedGroup);
      _loadGroups();
    } else if (selectedColor == null && group.color != null) {
      // 选择"无"时清除颜色
      final updatedGroup = group.copyWith(color: null);
      await FavoriteGroupService.updateGroup(updatedGroup);
      _loadGroups();
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> _togglePin(FavoriteGroup group) async {
    await FavoriteGroupService.togglePin(group.id);
    _loadGroups();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义分组'),
        actions: [
          IconButton(
            icon: const Icon(Icons.expand_less),
            onPressed: () {
              // 折叠/展开功能可以在这里实现
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 表头
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 40), // 删除按钮占位
                      Expanded(child: Text('分组名称')),
                      SizedBox(width: 40, child: Center(child: Text('颜色'))),
                      SizedBox(width: 40, child: Center(child: Text('编辑'))),
                      SizedBox(width: 40, child: Center(child: Text('置顶'))),
                      SizedBox(width: 40, child: Center(child: Text('拖动'))),
                    ],
                  ),
                ),
                // 分组列表
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: _groups.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      final item = _groups.removeAt(oldIndex);
                      _groups.insert(newIndex, item);
                      
                      // 更新顺序
                      final groupIds = _groups.map((g) => g.id).toList();
                      await FavoriteGroupService.updateGroupOrder(groupIds);
                      setState(() {});
                    },
                    itemBuilder: (context, index) {
                      final group = _groups[index];
                      return _buildGroupItem(group, index);
                    },
                  ),
                ),
                // 新建分组按钮
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: _createNewGroup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('新建自选分组'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildGroupItem(FavoriteGroup group, int index) {
    Color? groupColor;
    if (group.color != null) {
      try {
        groupColor = Color(int.parse(group.color!.substring(1), radix: 16) + 0xFF000000);
      } catch (e) {
        // 解析失败，使用默认颜色
      }
    }

    return Container(
      key: ValueKey(group.id),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // 删除按钮
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.red),
            onPressed: () => _deleteGroup(group),
            iconSize: 24,
          ),
          // 分组名称
          Expanded(
            child: Text(
              group.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 颜色
          InkWell(
            onTap: () => _selectColor(group),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: groupColor ?? Colors.transparent,
                shape: BoxShape.circle,
                border: groupColor == null
                    ? Border.all(color: Colors.grey[300]!)
                    : null,
              ),
              child: groupColor == null
                  ? const Icon(Icons.palette, size: 20, color: Colors.grey)
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          // 编辑按钮
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () => _editGroupName(group),
            color: Colors.blue,
          ),
          // 置顶按钮
          IconButton(
            icon: Icon(
              group.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 20,
            ),
            onPressed: () => _togglePin(group),
            color: group.isPinned ? Colors.orange : Colors.grey,
          ),
          // 拖动图标
          const Icon(
            Icons.drag_handle,
            size: 20,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }
}

