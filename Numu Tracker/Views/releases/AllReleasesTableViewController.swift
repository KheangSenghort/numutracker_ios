//
//  AllReleasesTableViewController.swift
//  Numu Tracker
//
//  Created by Bradley Root on 10/29/16.
//  Copyright © 2016 Numu Tracker. All rights reserved.
//

import UIKit
import Crashlytics

let defaults = UserDefaults.standard

class AllReleasesTableViewController: UITableViewController {

    var lastSelectedArtistId: String = ""
    var lastSelectedArtistName: String = ""
    var selectedIndexPath: IndexPath?
    var releases: [ReleaseItem] = []
    var viewName: String = ""
    var releaseData: ReleaseData! {
        didSet {
            if releaseData.totalPages == "0" {
                DispatchQueue.main.async(execute: {
                    self.tableView.tableHeaderView = self.noResultsFooterView
                    self.tableView.tableFooterView = UIView()
                    if self.slideType == 3 {
                        self.noResultsLabel.text = "After you've followed some artists, any releases (upcoming or past) added to the system will show up here.\n\nCheck back later."
                    } else if self.slideType == 2 {
                        self.noResultsLabel.text = "Any upcoming releases will appear here."
                    } else {
                        self.noResultsLabel.text = "No results.\n\nHave you followed some artists?\n\nPull to refresh when you have."
                    }
                })
            } else {
                DispatchQueue.main.async(execute: {
                    self.tableView.tableHeaderView = nil
                })
            }
        }
    }
    var isLoading: Bool = false
    var viewType: Int = 1
    var slideType: Int = 0

    @IBOutlet var footerView: UIView!
    @IBOutlet var noResultsFooterView: UIView!
    @IBOutlet weak var noResultsLabel: UILabel!

    @IBOutlet weak var releasesSegmentedControl: UISegmentedControl!

    @IBAction func changeSlide(_ sender: UISegmentedControl) {
        let segment = sender.selectedSegmentIndex
        self.slideType = segment
        self.tableView.tableFooterView = self.footerView
        self.selectedIndexPath = nil
        releases.removeAll()
        tableView.reloadData()
        self.loadFirstReleases()
    }

    func loadFirstReleases() {
        if defaults.logged {
            self.isLoading = true
            NumuClient.shared.getReleases(view: self.viewType, slide: self.slideType) {[weak self](releaseData) in
                self?.releaseData = releaseData
                DispatchQueue.main.async(execute: {
                    if let results = self?.releaseData?.results {
                        self?.releases = results
                    }
                    self?.isLoading = false
                    self?.tableView.reloadData()
                    self?.tableView.tableFooterView = UIView()
                    self?.refreshControl?.endRefreshing()
                })
            }

            switch (self.viewType, self.slideType) {
            case (0, 0):
                self.viewName = "All Unlistened"
            case (0, 1):
                self.viewName = "All Released"
            case (0, 2):
                self.viewName = "All Upcoming"
            case (0, 3):
                self.viewName = "Error"
            case (1, 0):
                self.viewName = "Your Unlistened"
            case (1, 1):
                self.viewName = "Your Released"
            case (1, 2):
                self.viewName = "Your Upcoming"
            case (1, 3):
                self.viewName = "Your Fresh"
            default:
                self.viewName = "Error"
            }

            Answers.logCustomEvent(withName: self.viewName, customAttributes: nil)
        }
    }

    func loadMoreReleases() {
        self.isLoading = true
        let currentPage = Int(self.releaseData.currentPage)!
        let nextPage = currentPage+1
        let offset = releases.count
        let limit = 50

        NumuClient.shared.getReleases(view: self.viewType, slide: self.slideType, page: nextPage, limit: limit, offset: offset) {[weak self](releaseData) in
            self?.releaseData = releaseData
            DispatchQueue.main.async(execute: {
                self?.releases = (self?.releases)! + (self?.releaseData?.results)!
                self?.isLoading = false
                self?.tableView.reloadData()
                self?.tableView.tableFooterView = UIView()
            })
        }
    }

    override func viewDidLoad() {
        
        super.viewDidLoad()

        viewType = 1
        self.title = "Your Releases"

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(actOnLoggedInNotification),
                                               name: .LoggedIn,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(actOnLoggedOutNotification),
                                               name: .LoggedOut,
                                               object: nil)

        self.refreshControl?.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)

        self.tableView.tableFooterView = self.footerView
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.releases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> ReleaseTableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "releaseInfoCell", for: indexPath) as! ReleaseTableViewCell

        let releaseInfo = releases[indexPath.row]
        cell.configure(releaseInfo: releaseInfo)

        // Image loading.
        cell.artIndicator.startAnimating()
        cell.thumbUrl = releaseInfo.thumbUrl // For recycled cells' late image loads.

        if let image = releaseInfo.thumbUrl.cachedImage {
            // Cached: set immediately.
            cell.artImageView.image = image
            cell.artImageView.alpha = 1
        } else {
            // Not cached, so load then fade it in.
            cell.artImageView.alpha = 0
            releaseInfo.thumbUrl.fetchImage { image in
                // Check the cell hasn't recycled while loading.
                if cell.thumbUrl == releaseInfo.thumbUrl {
                    cell.artImageView.image = image
                    UIView.animate(withDuration: 0.3) {
                        cell.artImageView.alpha = 1
                    }
                }
            }
        }

        let rowsToLoadFromBottom = 20

        if !self.isLoading && indexPath.row >= (releases.count - rowsToLoadFromBottom) {
            let currentPage = Int(releaseData.currentPage)!
            let totalPages = Int(releaseData.totalPages)!
            if currentPage < totalPages {
                self.tableView.tableFooterView = self.footerView
                self.loadMoreReleases()
            }
        }

        return cell
    }

    @objc func handleRefresh(refreshControl: UIRefreshControl) {
        releases.removeAll()
        tableView.reloadData()
        self.loadFirstReleases()
    }

    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {

        let releaseInfo = self.releases[indexPath.row]

        let listened = UITableViewRowAction(style: .normal, title: "Listened") { action, index in
            
            releaseInfo.toggleListenStatus() { (success) in
                DispatchQueue.main.async(execute: {
                    if success == "1" {
                        // remove or add unread marker back in
                        let cell = self.tableView.cellForRow(at: indexPath) as! ReleaseTableViewCell
                        if self.releases[indexPath.row].listenStatus == "0" {
                            self.releases[indexPath.row].listenStatus = "1"
                            cell.listenedIndicatorView.isHidden = true
                            Answers.logCustomEvent(
                                withName: "Listened",
                                customAttributes: ["Release ID": releaseInfo.releaseId])
                        } else {
                            self.releases[indexPath.row].listenStatus = "0"
                            cell.listenedIndicatorView.isHidden = false
                             Answers.logCustomEvent(
                                withName: "Unlistened",
                                customAttributes: ["Release ID": releaseInfo.releaseId])
                        }
                        tableView.setEditing(false, animated: true)
                    }
                })
            }
        }

        if releaseInfo.listenStatus == "1" {
            listened.title = "Didn't Listen"
        }
        listened.backgroundColor = .background

        return [listened]
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let previousIndexPath = selectedIndexPath
        if indexPath == selectedIndexPath {
            selectedIndexPath = nil
        } else {
            selectedIndexPath = indexPath
        }

        var indexPaths: Array<IndexPath> = []
        if let previous = previousIndexPath {
            indexPaths += [previous]
        }
        if let current = selectedIndexPath {
            indexPaths += [current]
        }
        if !indexPaths.isEmpty {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }
    override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath) {
        (cell as! ReleaseTableViewCell).watchFrameChanges()
    }

    override func tableView(
        _ tableView: UITableView,
        didEndDisplaying cell: UITableViewCell,
        forRowAt indexPath: IndexPath) {
        (cell as! ReleaseTableViewCell).ignoreFrameChanges()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        for cell in tableView.visibleCells as! [ReleaseTableViewCell] {
            cell.ignoreFrameChanges()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        for cell in tableView.visibleCells as! [ReleaseTableViewCell] {
            cell.watchFrameChanges()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath == selectedIndexPath {
            return ReleaseTableViewCell.expandedHeight
        } else {
            return ReleaseTableViewCell.defaultHeight
        }
    }

    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {

        if segue.identifier == "showArtistReleases",
            let destination = segue.destination as? ArtistReleasesTableViewController,
            let releaseIndex = tableView.indexPathForSelectedRow?.row {
            let artistId = releases[releaseIndex].artistId
            let artistName = releases[releaseIndex].artistName
            self.lastSelectedArtistId = artistId
            self.lastSelectedArtistName = artistName
            destination.artistId = artistId
            destination.artistName = artistName
        } else if segue.identifier == "showArtistReleases",
            let destination = segue.destination as? ArtistReleasesTableViewController {
            destination.artistId = self.lastSelectedArtistId
            destination.artistName = self.lastSelectedArtistName
        }
    }

    @objc func actOnLoggedInNotification() {
        releases.removeAll()
        tableView.reloadData()
        self.tableView.tableFooterView = self.footerView
        DispatchQueue.global(qos: .background).async(execute: {
            self.loadFirstReleases()
            DispatchQueue.main.async(execute: {
                self.tableView.reloadData()
                self.tableView.tableFooterView = UIView()
            })
        })
    }

    @objc func actOnLoggedOutNotification() {
        releases.removeAll()
        tableView.reloadData()
        DispatchQueue.global(qos: .background).async(execute: {
            self.loadFirstReleases()
            DispatchQueue.main.async(execute: {
                self.tableView.reloadData()
            })
        })
    }
}
