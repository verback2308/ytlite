import UIKit

// MARK: - Search filters UI

extension SearchViewController {
    func setupFiltersButton() {
        filtersButton.target = self
        filtersButton.action = #selector(filtersTapped)
        navigationItem.rightBarButtonItem = filtersButton
        updateFiltersButton()
    }

    private func updateFiltersButton() {
        filtersButton.title = filters.isDefault ? "Filters" : "Filters •"
    }

    @objc
    private func filtersTapped() {
        let sheet = UIAlertController(
            title: "搜索过滤器", message: nil, preferredStyle: .actionSheet
        )
        addFilterActions(to: sheet)
        if !filters.isDefault {
            sheet.addAction(
                UIAlertAction(
                    title: "重置过滤器",
                    style: .destructive
                ) { [weak self] _ in
                    self?.apply { $0 = SearchFilters() }
                }
            )
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = filtersButton
        present(sheet, animated: true)
    }

    private func addFilterActions(to sheet: UIAlertController) {
        sheet.addAction(
            UIAlertAction(
                title: "排序: \(filters.sort.displayName)", style: .default
            ) { [weak self] _ in
                self?.showSortPicker()
            }
        )
        sheet.addAction(
            UIAlertAction(
                title: "日期: \(filters.uploadDate.displayName)",
                style: .default
            ) { [weak self] _ in
                self?.showDatePicker()
            }
        )
        sheet.addAction(
            UIAlertAction(
                title: "类型: \(filters.type.displayName)", style: .default
            ) { [weak self] _ in
                self?.showTypePicker()
            }
        )
        sheet.addAction(
            UIAlertAction(
                title: "持续时间: \(filters.duration.displayName)",
                style: .default
            ) { [weak self] _ in
                self?.showDurationPicker()
            }
        )
    }

    // MARK: - Pickers

    private func showSortPicker() {
        presentOptions(
            title: "排序依据",
            names: SearchFilters.Sort.allCases.map { $0.displayName },
            selectedIndex: filters.sort.rawValue
        ) { [weak self] index in
            self?.apply { $0.sort = SearchFilters.Sort(rawValue: index) ?? .relevance }
        }
    }

    private func showDatePicker() {
        presentOptions(
            title: "上传日期",
            names: SearchFilters.UploadDate.allCases.map { $0.displayName },
            selectedIndex: filters.uploadDate.rawValue
        ) { [weak self] index in
            self?.apply {
                $0.uploadDate = SearchFilters.UploadDate(rawValue: index) ?? .any
            }
        }
    }

    private func showTypePicker() {
        presentOptions(
            title: "类型",
            names: SearchFilters.ContentType.allCases.map { $0.displayName },
            selectedIndex: filters.type.rawValue
        ) { [weak self] index in
            self?.apply {
                $0.type = SearchFilters.ContentType(rawValue: index) ?? .any
            }
        }
    }

    private func showDurationPicker() {
        presentOptions(
            title: "持续时间",
            names: SearchFilters.Duration.allCases.map { $0.displayName },
            selectedIndex: filters.duration.rawValue
        ) { [weak self] index in
            self?.apply {
                $0.duration = SearchFilters.Duration(rawValue: index) ?? .any
            }
        }
    }

    // MARK: - Helpers

    /// `rawValue` doubles as the option index — all filter enums are
    /// declared in raw-value order.
    private func presentOptions(
        title: String,
        names: [String],
        selectedIndex: Int,
        onPick: @escaping (Int) -> Void
    ) {
        let sheet = UIAlertController(
            title: title, message: nil, preferredStyle: .actionSheet
        )
        for (index, name) in names.enumerated() {
            let action = UIAlertAction(title: name, style: .default) { _ in
                onPick(index)
            }
            if index == selectedIndex {
                action.setValue(true, forKey: "checked")
            }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = filtersButton
        present(sheet, animated: true)
    }

    private func apply(_ change: (inout SearchFilters) -> Void) {
        change(&filters)
        updateFiltersButton()
        if !lastQuery.isEmpty {
            search(query: lastQuery)
        }
    }
}
