#include "ConflictDialog.h"

#include <QCheckBox>
#include <QFileInfo>
#include <QFormLayout>
#include <QLabel>
#include <QLocale>
#include <QPushButton>
#include <QVBoxLayout>

static QString describe(const QString &path) {
    QFileInfo fi(path);
    QLocale loc;
    if (fi.isDir()) {
        return QObject::tr("%1<br><i>directory · modified %2</i>")
            .arg(path.toHtmlEscaped(),
                 QLocale().toString(fi.lastModified(), QLocale::ShortFormat));
    }
    return QObject::tr("%1<br><i>%2 · modified %3</i>")
        .arg(path.toHtmlEscaped(),
             loc.formattedDataSize(fi.size()),
             QLocale().toString(fi.lastModified(), QLocale::ShortFormat));
}

ConflictDialog::ConflictDialog(const QString &src, const QString &dst, bool isDir,
                                QWidget *parent)
    : QDialog(parent) {
    setWindowTitle(tr("File already exists"));
    resize(520, 220);

    auto *title = new QLabel(
        isDir ? tr("<b>Directory already exists at the destination.</b>")
              : tr("<b>A file already exists at the destination.</b>"),
        this);

    auto *srcLbl = new QLabel(tr("<b>Source:</b><br>") + describe(src), this);
    srcLbl->setTextFormat(Qt::RichText);
    srcLbl->setWordWrap(true);
    auto *dstLbl = new QLabel(tr("<b>Destination:</b><br>") + describe(dst), this);
    dstLbl->setTextFormat(Qt::RichText);
    dstLbl->setWordWrap(true);

    m_applyAll = new QCheckBox(tr("Apply to all remaining conflicts"), this);

    auto *replace  = new QPushButton(tr("&Replace"),  this);
    auto *skip     = new QPushButton(tr("&Skip"),     this);
    auto *both     = new QPushButton(tr("&Keep both"), this);
    auto *merge    = new QPushButton(tr("&Merge"),    this);
    auto *cancel   = new QPushButton(tr("&Cancel all"), this);

    merge->setVisible(isDir);
    skip->setDefault(true);

    connect(replace, &QPushButton::clicked, this, [this]{ setAction(Replace); });
    connect(skip,    &QPushButton::clicked, this, [this]{ setAction(Skip); });
    connect(both,    &QPushButton::clicked, this, [this]{ setAction(KeepBoth); });
    connect(merge,   &QPushButton::clicked, this, [this]{ setAction(Merge); });
    connect(cancel,  &QPushButton::clicked, this, [this]{ setAction(CancelAll); });

    auto *btnRow = new QHBoxLayout;
    btnRow->addStretch(1);
    btnRow->addWidget(replace);
    btnRow->addWidget(skip);
    btnRow->addWidget(both);
    btnRow->addWidget(merge);
    btnRow->addWidget(cancel);

    auto *main = new QVBoxLayout(this);
    main->addWidget(title);
    main->addSpacing(6);
    main->addWidget(srcLbl);
    main->addWidget(dstLbl);
    main->addStretch(1);
    main->addWidget(m_applyAll);
    main->addLayout(btnRow);
}

bool ConflictDialog::applyToAll() const {
    return m_applyAll && m_applyAll->isChecked();
}

void ConflictDialog::setAction(int a) {
    m_action = a;
    accept();
}
