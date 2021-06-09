/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import UIKit

struct SettingsUX {
    static let TableViewHeaderFooterHeight = CGFloat(44)
}

extension UILabel {
    // iOS bug: NSAttributed string color is ignored without setting font/color to nil
    func assign(attributed: NSAttributedString?) {
        guard let attributed = attributed else { return }
        let attribs = attributed.attributes(at: 0, effectiveRange: nil)
        if attribs[NSAttributedString.Key.foregroundColor] == nil {
            // If the text color attribute isn't set, use the table view row text color.
            textColor = UIColor.theme.tableView.rowText
        } else {
            textColor = nil
        }
        attributedText = attributed
    }
}

// A base setting class that shows a title. You probably want to subclass this, not use it directly.
class Setting: NSObject {
    fileprivate var _title: NSAttributedString?
    fileprivate var _footerTitle: NSAttributedString?
    fileprivate var _cellHeight: CGFloat?
    fileprivate var _image: UIImage?

    weak var delegate: SettingsDelegate?

    // The url the SettingsContentViewController will show, e.g. Licenses and Privacy Policy.
    var url: URL? { return nil }

    // The title shown on the pref.
    var title: NSAttributedString? { return _title }
    var footerTitle: NSAttributedString? { return _footerTitle }
    var cellHeight: CGFloat? { return _cellHeight}
    fileprivate(set) var accessibilityIdentifier: String?

    // An optional second line of text shown on the pref.
    var status: NSAttributedString? { return nil }

    // Whether or not to show this pref.
    var hidden: Bool { return false }

    var style: UITableViewCell.CellStyle { return .subtitle }

    var accessoryType: UITableViewCell.AccessoryType { return .none }

    var accessoryView: UIImageView? { return nil }

    var textAlignment: NSTextAlignment { return .natural }

    var image: UIImage? { return _image }

    var enabled: Bool = true

    var isLinkStyle: Bool = false

    func accessoryButtonTapped() { onAccessoryButtonTapped?() }
    var onAccessoryButtonTapped: (() -> Void)?

    // Called when the cell is setup. Call if you need the default behaviour.
    func onConfigureCell(_ cell: UITableViewCell) {
        cell.detailTextLabel?.assign(attributed: status)
        cell.detailTextLabel?.attributedText = status
        cell.detailTextLabel?.numberOfLines = 0
        cell.textLabel?.assign(attributed: title)
        cell.textLabel?.textAlignment = textAlignment
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.lineBreakMode = .byTruncatingTail
        cell.accessoryType = accessoryType
        cell.accessoryView = accessoryView
        cell.selectionStyle = enabled ? .default : .none
        cell.accessibilityIdentifier = accessibilityIdentifier
        cell.imageView?.image = image
        if let title = title?.string {
            if let detailText = cell.detailTextLabel?.text {
                cell.accessibilityLabel = "\(title), \(detailText)"
            } else if let status = status?.string {
                cell.accessibilityLabel = "\(title), \(status)"
            } else {
                cell.accessibilityLabel = title
            }
        }
        cell.accessibilityTraits = UIAccessibilityTraits.button
        cell.indentationWidth = 0
        cell.layoutMargins = .zero
        
        let backgroundView = UIView()
        backgroundView.backgroundColor = UIColor.theme.tableView.selectedBackground
        backgroundView.bounds = cell.bounds
        cell.selectedBackgroundView = backgroundView
        
        // So that the separator line goes all the way to the left edge.
        cell.separatorInset = .zero
        if let cell = cell as? ThemedTableViewCell {
            cell.applyTheme()
        }

        if self.isLinkStyle {
            cell.textLabel?.textColor = UIColor.systemBlue
        }
    }

    // Called when the pref is tapped.
    func onClick(_ navigationController: UINavigationController?) { return }

    // Called when the pref is long-pressed.
    func onLongPress(_ navigationController: UINavigationController?) { return }

    init(title: NSAttributedString? = nil, footerTitle: NSAttributedString? = nil, cellHeight: CGFloat? = nil, delegate: SettingsDelegate? = nil, enabled: Bool? = nil, isLinkStyle: Bool? = nil) {
        self._title = title
        self._footerTitle = footerTitle
        self._cellHeight = cellHeight
        self.delegate = delegate
        self.enabled = enabled ?? true
        self.isLinkStyle = isLinkStyle ?? false
    }
}

// A setting in the sections panel. Contains a sublist of Settings
class SettingSection: Setting {
    fileprivate let children: [Setting]
    let paragraphTitle: Bool

    init(title: NSAttributedString? = nil, footerTitle: NSAttributedString? = nil, cellHeight: CGFloat? = nil, children: [Setting], paragraphTitle: Bool? = nil) {
        self.children = children
        self.paragraphTitle = paragraphTitle ?? false
        super.init(title: title, footerTitle: footerTitle, cellHeight: cellHeight)
    }

    var count: Int {
        var count = 0
        for setting in children where !setting.hidden {
            count += 1
        }
        return count
    }

    subscript(val: Int) -> Setting? {
        var i = 0
        for setting in children where !setting.hidden {
            if i == val {
                return setting
            }
            i += 1
        }
        return nil
    }
}

private class PaddedSwitch: UIView {
    fileprivate static let Padding: CGFloat = 8

    init(switchView: UISwitch) {
        super.init(frame: .zero)

        addSubview(switchView)

        frame.size = CGSize(width: switchView.frame.width + PaddedSwitch.Padding, height: switchView.frame.height)
        switchView.frame.origin = CGPoint(x: PaddedSwitch.Padding, y: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// A helper class for settings with a UISwitch.
// Takes and optional settingsDidChange callback and status text.
class BoolSetting: Setting {
    let prefKey: String? // Sometimes a subclass will manage its own pref setting. In that case the prefkey will be nil

    fileprivate let defaultValue: Bool
    fileprivate let settingDidChange: ((Bool) -> Void)?
    fileprivate let statusText: NSAttributedString?

    init(prefKey: String? = nil, defaultValue: Bool, attributedTitleText: NSAttributedString, attributedStatusText: NSAttributedString? = nil, settingDidChange: ((Bool) -> Void)? = nil) {
        self.prefKey = prefKey
        self.defaultValue = defaultValue
        self.settingDidChange = settingDidChange
        self.statusText = attributedStatusText
        super.init(title: attributedTitleText)
    }

    convenience init(prefKey: String? = nil, defaultValue: Bool, titleText: String, statusText: String? = nil, settingDidChange: ((Bool) -> Void)? = nil) {
        var statusTextAttributedString: NSAttributedString?
        if let statusTextString = statusText {
            statusTextAttributedString = NSAttributedString(string: statusTextString, attributes: [NSAttributedString.Key.foregroundColor: UIColor.theme.tableView.headerTextLight])
        }
        self.init(prefKey: prefKey, defaultValue: defaultValue, attributedTitleText: NSAttributedString(string: titleText, attributes: [NSAttributedString.Key.foregroundColor: UIColor.theme.tableView.rowText]), attributedStatusText: statusTextAttributedString, settingDidChange: settingDidChange)
    }

    override var status: NSAttributedString? {
        return statusText
    }

    override func onConfigureCell(_ cell: UITableViewCell) {
        super.onConfigureCell(cell)

        let control = UISwitchThemed()
        control.onTintColor = UIConstants.SystemBlueColor
        control.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        control.accessibilityIdentifier = prefKey?.replacingOccurrences(of: "profile.", with: "")

        displayBool(control)
        if let title = title {
            if let status = status {
                control.accessibilityLabel = "\(title.string), \(status.string)"
            } else {
                control.accessibilityLabel = title.string
            }
            cell.accessibilityLabel = nil
        }
        cell.accessoryView = PaddedSwitch(switchView: control)
        cell.selectionStyle = .none
    }

    @objc func switchValueChanged(_ control: UISwitch) {
        writeBool(control)
        settingDidChange?(control.isOn)
        TelemetryWrapper.recordEvent(category: .action, method: .change, object: .setting, extras: ["pref": prefKey as Any, "to": control.isOn])
    }

    // These methods allow a subclass to control how the pref is saved
    func displayBool(_ control: UISwitch) {
        guard let key = prefKey else {
            return
        }
        control.isOn = UserDefaults.standard.bool(forKey: key)
    }

    func writeBool(_ control: UISwitch) {
        guard let key = prefKey else {
            return
        }
        UserDefaults.standard.set(control.isOn, forKey: key)
    }
}

enum CheckmarkSettingStyle {
    case leftSide
    case rightSide
}

class CheckmarkSetting: Setting {
    let onChecked: () -> Void
    let isChecked: () -> Bool
    private let subtitle: NSAttributedString?
    let checkmarkStyle: CheckmarkSettingStyle

    override var status: NSAttributedString? {
        return subtitle
    }

    init(title: NSAttributedString, style: CheckmarkSettingStyle = .rightSide, subtitle: NSAttributedString?, accessibilityIdentifier: String? = nil, isChecked: @escaping () -> Bool, onChecked: @escaping () -> Void) {
        self.subtitle = subtitle
        self.onChecked = onChecked
        self.isChecked = isChecked
        self.checkmarkStyle = style
        super.init(title: title)
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    override func onConfigureCell(_ cell: UITableViewCell) {
        super.onConfigureCell(cell)

        if checkmarkStyle == .rightSide {
            cell.accessoryType = .checkmark
            cell.tintColor = isChecked() ? UIColor.theme.tableView.rowActionAccessory : UIColor.clear
        } else {
            let window = UIApplication.shared.keyWindow
            let safeAreaInsets = window?.safeAreaInsets.left ?? 0
            cell.indentationWidth = 42 + safeAreaInsets
            cell.indentationLevel = 1

            cell.accessoryType = .detailButton
            cell.tintColor = UIColor.theme.tableView.rowActionAccessory // Sets accessory color only

            let checkColor = isChecked() ? UIColor.theme.tableView.rowActionAccessory : UIColor.clear
            let check = UILabel(frame: CGRect(x: 20, y: 10, width: 24, height: 20))
            cell.contentView.addSubview(check)
            check.text = "\u{2713}"
            check.font = UIFont.systemFont(ofSize: 20)
            check.textColor = checkColor

            let result = NSMutableAttributedString()
            if let str = title?.string {
                result.append(NSAttributedString(string: str, attributes: [NSAttributedString.Key.foregroundColor: UIColor.theme.tableView.rowText]))
            }
            cell.textLabel?.assign(attributed: result)
        }

        if !enabled {
            cell.subviews.forEach { $0.alpha = 0.5 }
        }
    }

    override func onClick(_ navigationController: UINavigationController?) {
        // Force editing to end for any focused text fields so they can finish up validation first.
        navigationController?.view.endEditing(true)
        if !isChecked() {
            onChecked()
        }
    }
}

@objc
protocol SettingsDelegate: AnyObject {
    func settingsOpenURLInNewTab(_ url: URL)
    func settingsOpenURLInNewNonPrivateTab(_ url: URL)
}

// The base settings view controller.
class SettingsTableViewController: ThemedTableViewController {

    typealias SettingsGenerator = (SettingsTableViewController, SettingsDelegate?) -> [SettingSection]

    fileprivate let Identifier = "CellIdentifier"
    fileprivate let SectionHeaderIdentifier = "SectionHeaderIdentifier"
    var settings = [SettingSection]()

    weak var settingsDelegate: SettingsDelegate?

    var profile: Profile!
    var tabManager: TabManager!

    /// Used to calculate cell heights.
    fileprivate lazy var dummyToggleCell: UITableViewCell = {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "dummyCell")
        cell.accessoryView = UISwitchThemed()
        return cell
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Identifier)
        tableView.register(ThemedTableSectionHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderIdentifier)
        tableView.tableFooterView = UIView(frame: CGRect(width: view.frame.width, height: 30))
        tableView.estimatedRowHeight = 44
        tableView.estimatedSectionHeaderHeight = 44

        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress))
        tableView.addGestureRecognizer(longPressGestureRecognizer)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        settings = generateSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(syncDidChangeState), name: .ProfileDidStartSyncing, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(syncDidChangeState), name: .ProfileDidFinishSyncing, object: nil)

        applyTheme()
    }

    override func applyTheme() {
        settings = generateSettings()
        super.applyTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        [Notification.Name.ProfileDidStartSyncing, Notification.Name.ProfileDidFinishSyncing].forEach { name in
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
    }

    // Override to provide settings in subclasses
    func generateSettings() -> [SettingSection] {
        return []
    }

    @objc fileprivate func syncDidChangeState() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }

    @objc fileprivate func refresh() {
        // Through-out, be aware that modifying the control while a refresh is in progress is /not/ supported and will likely crash the app.
        ////self.profile.rustAccount.refreshProfile()
        // TODO [rustfxa] listen to notification and refresh profile
    }

    @objc func didLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        let location = gestureRecognizer.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: location), gestureRecognizer.state == .began else {
            return
        }

        let section = settings[indexPath.section]
        if let setting = section[indexPath.row], setting.enabled {
            setting.onLongPress(navigationController)
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = settings[indexPath.section]
        if let setting = section[indexPath.row] {
            let cell = ThemedTableViewCell(style: setting.style, reuseIdentifier: nil)
            setting.onConfigureCell(cell)
            cell.backgroundColor = UIColor.theme.tableView.rowBackground
            return cell
        }
        return super.tableView(tableView, cellForRowAt: indexPath)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return settings.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = settings[section]
        return section.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderIdentifier) as? ThemedTableSectionHeaderFooterView else {
            return nil
        }

        let sectionSetting = settings[section]
        let sectionTitle = sectionSetting.title?.string

        if sectionTitle?.isEmpty == false {
            if sectionSetting.paragraphTitle {
                var title = sectionTitle ?? "";
                title += "\n"
                headerView.titleLabel.text = title
                headerView.titleLabel.font = UIFont.systemFont(ofSize: 17)
            } else {
                headerView.titleLabel.text = sectionTitle?.uppercased()
            }
        }

        headerView.applyTheme()
        return headerView
    }

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let sectionSetting = settings[section]
        guard let sectionFooter = sectionSetting.footerTitle?.string else {
            return nil
        }
        let footerView = ThemedTableSectionHeaderFooterView()
        footerView.titleLabel.text = sectionFooter
        footerView.titleAlignment = .top
        footerView.applyTheme()
        return footerView
    }

    // To hide a footer dynamically requires returning nil from viewForFooterInSection
    // and setting the height to zero.
    // However, we also want the height dynamically calculated, there is a magic constant
    // for that: `UITableViewAutomaticDimension`.
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        let sectionSetting = settings[section]
        if let _ = sectionSetting.footerTitle?.string {
            return UITableView.automaticDimension
        }
        return 0
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let section = settings[indexPath.section]
        if let setting = section[indexPath.row], let height = setting.cellHeight {
            return height
        }

        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let section = settings[indexPath.section]
        if let setting = section[indexPath.row], setting.enabled {
            setting.onClick(navigationController)
        }
    }

    fileprivate func heightForLabel(_ label: UILabel, width: CGFloat, text: String?) -> CGFloat {
        guard let text = text else { return 0 }

        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let attrs = [NSAttributedString.Key.font: label.font as Any]
        let boundingRect = NSString(string: text).boundingRect(with: size,
            options: .usesLineFragmentOrigin, attributes: attrs, context: nil)
        return boundingRect.height
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let section = settings[indexPath.section]
        if let setting = section[indexPath.row] {
            setting.accessoryButtonTapped()
        }
    }
}